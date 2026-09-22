#!/usr/bin/env python3
"""The app's line to iCloud: sign in, and move one asset to the bin or back.

    icloud_helper.py login   --username APPLE_ID [--save-config]
    icloud_helper.py find    --file PATH --ts EPOCH [--shared]
    icloud_helper.py delete  --key KEY --file PATH --ts EPOCH [--companion PATH] [--shared]
    icloud_helper.py restore --key KEY

`--shared` looks in the iCloud Shared Library the account is in instead of
the personal one; the sync tool puts those files under LIBRARY/shared.

`login` reads the password as the first line on stdin and, when Apple asks
for two-factor confirmation, prints {"step": "2fa"} and waits for the code
on the next stdin line. The session then lands in icloudpd's cookie
directory, so the sync tool works without ever seeing the password.

`delete` is the only thing that writes to the library. It flips the asset's
isDeleted flag, exactly what the Photos app on the phone does when you tap
the bin: the item lands in "Recently Deleted" and stays recoverable there
for 30 days. Nothing here can empty that folder. Locally the files move into
<cache>/trash/<key>/ with a manifest, so `restore` can put both halves back.

Every command prints JSON objects on stdout, one per line, and exits
non-zero on failure.
"""

import argparse
import json
import logging
import os
import shutil
import sys
import time
import urllib.parse
from pathlib import Path

from pyicloud_ipd.base import PyiCloudService
from pyicloud_ipd.exceptions import (
    PyiCloudAPIResponseException,
    PyiCloudConnectionErrorException,
    PyiCloudException,
    PyiCloudFailedLoginException,
    PyiCloudServiceUnavailableException,
)

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "omarchy-icloud-photos" / "config"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "omarchy-icloud-photos"
WALK_LIMIT = 600  # newest assets to inspect when looking for a filename
TS_TOLERANCE = 180  # seconds between local mtime and iCloud capture time
PHOTOS_PCS_COOKIES = ("X-APPLE-WEBAUTH-PCS-Photos", "X-APPLE-WEBAUTH-PCS-Sharing")
PCS_POLL_ATTEMPTS = 30
PCS_POLL_SECONDS = 10


def pcs_required_from_webservices(webservices):
    ws = webservices or {}
    for key in ("photos", "ckdatabasews"):
        if (ws.get(key) or {}).get("pcsRequired"):
            return True
    return False


def classify_icloudpd_log(text):
    lower = (text or "").lower()
    if "private db access disabled" in lower:
        return "pcs-required"
    if any(s in lower for s in ("authentication required for account", "two-factor", "2fa", "two-step", "please enter")):
        return "auth-required"
    return None


def acquire_photos_pcs(request_fn, cookie_names_fn, on_waiting=None, attempts=PCS_POLL_ATTEMPTS,
                       sleep_fn=time.sleep, interval=PCS_POLL_SECONDS):
    if set(PHOTOS_PCS_COOKIES) <= set(cookie_names_fn()):
        return "already"
    if on_waiting:
        on_waiting()
    for i in range(attempts):
        payload = request_fn() or {}
        if payload.get("status") == "success" and set(PHOTOS_PCS_COOKIES) <= set(cookie_names_fn()):
            return "acquired"
        if i + 1 < attempts:
            sleep_fn(interval)
    return "timeout"


def read_config(require_id=True):
    cfg = {"COOKIES": str(Path.home() / ".config" / "icloudpd")}
    if CONFIG.exists():
        for line in CONFIG.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            cfg[k.strip()] = os.path.expandvars(v.strip().strip('"').strip("'"))
    if require_id and "APPLE_ID" not in cfg:
        fail(f"APPLE_ID not set in {CONFIG}")
    return cfg


def save_apple_id(apple_id):
    """Set APPLE_ID in the config file, keeping every other line as it is."""
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    lines = CONFIG.read_text().splitlines() if CONFIG.exists() else [
        "# omarchy-icloud-photos configuration, sourced by omarchy-icloud-photos-sync",
        "LIBRARY=$HOME/Pictures/iCloud",
        "DAYS=7",
    ]
    out, done = [], False
    for line in lines:
        if line.strip().startswith("APPLE_ID="):
            out.append(f"APPLE_ID={apple_id}"); done = True
        else:
            out.append(line)
    if not done:
        out.insert(1, f"APPLE_ID={apple_id}")
    CONFIG.write_text("\n".join(out) + "\n")


def emit(obj):
    print(json.dumps(obj), flush=True)


def fail(message, **extra):
    logging.getLogger().error("fail: %s %s", message, extra if extra else "")
    print(json.dumps({"ok": False, "error": message, **extra}))
    sys.exit(1)


def session_cookie_names(session):
    return {c.name for c in session.cookies}


def request_photos_pcs(api):
    url = f"{api.SETUP_ENDPOINT}/requestPCS"
    body = json.dumps({"appName": "photos", "derivedFromUserAction": True})
    try:
        r = api.session.post(
            url, data=body, headers={"Content-type": "application/json"}, params=api.params
        )
        return r.json()
    except PyiCloudAPIResponseException as e:
        return {"status": "failure", "message": str(e)}
    except ValueError:
        return {"status": "failure", "message": "requestPCS returned no JSON"}


def ensure_photos_pcs(api, on_waiting=None):
    if not pcs_required_from_webservices(api.data.get("webservices")):
        return "skipped"
    result = acquire_photos_pcs(
        request_fn=lambda: request_photos_pcs(api),
        cookie_names_fn=lambda: session_cookie_names(api.session),
        on_waiting=on_waiting,
    )
    if result == "timeout":
        fail("Apple did not grant Photos access. Allow Access on a trusted iPhone or Mac, then try again.")
    try:
        api.session.cookies.save(ignore_discard=True, ignore_expires=True)
    except Exception:
        pass
    return result


def connect(cfg, require_pcs=True):
    # The constructor signs in by itself (session token first, password if
    # needed). Calling authenticate() again would be a second sign-in in a
    # row, which Apple answers with a 503.
    api = PyiCloudService("com", cfg["APPLE_ID"], lambda: None, cookie_directory=cfg["COOKIES"])
    if api.requires_2fa:
        fail("iCloud session expired. Sign in again.", need="login")
    if require_pcs and pcs_required_from_webservices(api.data.get("webservices")):
        if not set(PHOTOS_PCS_COOKIES) <= session_cookie_names(api.session):
            fail("iCloud Photos needs device approval.", need="pcs")
    return api


def find_asset(album, name, ts):
    """Newest-first walk until the asset with this filename and capture time."""
    seen = 0
    for asset in album:
        seen += 1
        if asset.filename == name and abs(asset.created.timestamp() - ts) <= TS_TOLERANCE:
            return asset
        if seen >= WALK_LIMIT:
            break
    return None


def libraries(api, shared):
    """(zone name, library) pairs to search: the personal library, or the
    Shared Library. Apple allows one per account, and where it turns up
    depends on who made it: the owner finds its SharedSync zone in the
    private database next to PrimarySync, a participant in the shared one."""
    if not shared:
        return [("PrimarySync", api.photos)]
    out = [(z, lib) for z, lib in api.photos.private_libraries.items() if z != "PrimarySync"]
    out += list(api.photos.shared_libraries.items())
    return out


def locate(api, name, ts, shared):
    """The asset with this name and time, and the library it lives in."""
    for zone, library in libraries(api, shared):
        asset = find_asset(library.all, name, ts)
        if asset is not None:
            return zone, library, asset
    fail("asset not found in the newest items of the " + ("shared" if shared else "personal") + " library")


def library_by_zone(api, zone):
    if not zone or zone == "PrimarySync":
        return api.photos
    library = api.photos.private_libraries.get(zone) or api.photos.shared_libraries.get(zone)
    if library is None:
        fail(f"the shared library {zone} is no longer available")
    return library


def describe(asset):
    rec = asset._asset_record
    return {
        "record": rec["recordName"],
        "changeTag": rec["recordChangeTag"],
        "filename": asset.filename,
        "created": asset.created.isoformat(),
        "size": asset.size,
    }


def set_deleted(library, record_name, change_tag, deleted):
    url = f"{library.service_endpoint}/records/modify?{urllib.parse.urlencode(library.params)}"
    body = {
        "atomic": True,
        "desiredKeys": ["isDeleted"],
        "operations": [{
            "operationType": "update",
            "record": {
                "fields": {"isDeleted": {"value": 1 if deleted else 0}},
                "recordChangeTag": change_tag,
                "recordName": record_name,
                "recordType": "CPLAsset",
            },
        }],
        "zoneID": library.zone_id,
    }
    r = library.session.post(url, data=json.dumps(body), headers={"Content-type": "application/json"})
    data = r.json()
    records = data.get("records") or []
    if not records or "serverErrorCode" in records[0]:
        fail("iCloud refused the change", response=data)
    return records[0].get("recordChangeTag", change_tag)


def demo(cfg):
    return cfg.get("DEMO") == "1"


def cmd_login(args, cfg):
    password = sys.stdin.readline().rstrip("\n")
    # Length and character class only, never the password: enough to tell a
    # typo from a transport problem when Apple answers 401.
    logging.getLogger().info("password: %d characters, non-ascii=%s, ends with space=%s",
                             len(password), any(ord(c) > 127 for c in password), password.endswith(" "))
    if demo(cfg):
        emit({"ok": True, "username": args.username})
        return
    cookies = cfg["COOKIES"]
    # Apple answers 503 on the sign-in front door when it has seen too many
    # sign-ins for the account in a short time, and every new attempt,
    # including an automatic retry, stretches that window. So: one attempt,
    # and on a 503 a clear request to leave it alone for a while.
    try:
        api = PyiCloudService("com", args.username, lambda: password or None, cookie_directory=cookies)
    except PyiCloudFailedLoginException:
        fail("Wrong Apple ID or password")
    except PyiCloudServiceUnavailableException:
        logging.getLogger().warning("503 during authenticate")
        fail("Apple is not taking sign-ins for this account right now, which happens after "
             "several sign-ins in a short time. Leave it for half an hour, then try once; "
             "every attempt before that extends the wait.")
    except PyiCloudConnectionErrorException:
        fail("Could not reach iCloud. Check the connection and try again.")
    except PyiCloudException as e:
        fail(f"Apple did not accept the login: {e}")
    if api.requires_2fa:
        # Ask Apple to push a code to the trusted devices. Apple usually pushes
        # one on the sign-in itself already, and this endpoint answers 503 at
        # times; pyicloud only swallows API errors, not that one, so guard it
        # here. Without the guard a working sign-in looked rate-limited.
        try:
            api.trigger_push_notification()
        except PyiCloudException as e:
            print(f"push notification not sent: {e}", file=sys.stderr)
        emit({"step": "2fa"})
        code = sys.stdin.readline().strip()
        if not (len(code) == 6 and code.isdigit()):
            fail("The code should be six digits")
        if not api.validate_2fa_code(code):
            fail("Apple did not accept that code")
        api.trust_session()
    if args.save_config:
        save_apple_id(args.username)
    notified = []

    def waiting():
        if not notified:
            notified.append(True)
            logging.getLogger().info("waiting for Photos device approval (PCS)")
            emit({"step": "pcs"})

    try:
        ensure_photos_pcs(api, on_waiting=waiting)
    except PyiCloudException as e:
        fail(f"Could not open the Photos library: {e}")
    emit({"ok": True, "username": args.username})


def cmd_pcs(args, cfg):
    if demo(cfg):
        emit({"ok": True, "username": cfg.get("APPLE_ID", "")})
        return
    api = connect(cfg, require_pcs=False)
    notified = []

    def waiting():
        if not notified:
            notified.append(True)
            logging.getLogger().info("waiting for Photos device approval (PCS)")
            emit({"step": "pcs"})

    try:
        ensure_photos_pcs(api, on_waiting=waiting)
    except PyiCloudException as e:
        fail(f"Could not open the Photos library: {e}")
    emit({"ok": True, "username": cfg["APPLE_ID"]})


def cmd_find(args, cfg):
    api = connect(cfg)
    zone, _, asset = locate(api, os.path.basename(args.file), args.ts, args.shared)
    print(json.dumps({"ok": True, "library": zone, **describe(asset)}))


def cmd_delete(args, cfg):
    files = [args.file] + ([args.companion] if args.companion else [])
    for f in files:
        if not os.path.isfile(f):
            fail(f"not a file: {f}")
    if demo(cfg):
        info = {"record": "demo", "changeTag": "", "filename": os.path.basename(args.file), "created": "", "size": 0}
        zone, new_tag = ("demo-shared" if args.shared else "PrimarySync"), ""
    else:
        api = connect(cfg)
        zone, library, asset = locate(api, os.path.basename(args.file), args.ts, args.shared)
        info = describe(asset)
        new_tag = set_deleted(library, info["record"], info["changeTag"], True)

    trash_dir = CACHE / "trash" / args.key
    trash_dir.mkdir(parents=True, exist_ok=True)
    moved = []
    for f in files:
        dest = trash_dir / os.path.basename(f)
        shutil.move(f, dest)
        moved.append([f, str(dest)])
    manifest = {**info, "library": zone, "changeTag": new_tag, "files": moved}
    (CACHE / "trash" / f"{args.key}.json").write_text(json.dumps(manifest, indent=2))
    print(json.dumps({"ok": True, "key": args.key, **info}))


def cmd_restore(args, cfg):
    manifest_path = CACHE / "trash" / f"{args.key}.json"
    if not manifest_path.exists():
        fail("nothing to restore for this key")
    manifest = json.loads(manifest_path.read_text())
    if not demo(cfg):
        api = connect(cfg)
        library = library_by_zone(api, manifest.get("library"))
        # The change tag moves on every edit; look the record up in Recently
        # Deleted for a fresh one and fall back to the tag we saved.
        tag = manifest["changeTag"]
        seen = 0
        for asset in library.recently_deleted:
            seen += 1
            if asset._asset_record["recordName"] == manifest["record"]:
                tag = asset._asset_record["recordChangeTag"]
                break
            if seen >= WALK_LIMIT:
                break
        set_deleted(library, manifest["record"], tag, False)

    for src, dest in manifest["files"]:
        if os.path.isfile(dest):
            os.makedirs(os.path.dirname(src), exist_ok=True)
            shutil.move(dest, src)
    shutil.rmtree(manifest_path.with_suffix(""), ignore_errors=True)
    manifest_path.unlink()
    print(json.dumps({"ok": True, "key": args.key, "record": manifest["record"], "filename": manifest["filename"]}))


def main():
    # Everything pyicloud says goes to <cache>/helper.log so a failed sign-in
    # can be understood afterwards. Passwords are masked by pyicloud itself.
    CACHE.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(filename=CACHE / "helper.log", level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    os.chmod(CACHE / "helper.log", 0o600)
    logging.getLogger().info("helper %s", " ".join(sys.argv[1:]))
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    l = sub.add_parser("login"); l.add_argument("--username", required=True); l.add_argument("--save-config", action="store_true")
    f = sub.add_parser("find"); f.add_argument("--file", required=True); f.add_argument("--ts", type=int, required=True)
    f.add_argument("--shared", action="store_true")
    d = sub.add_parser("delete"); d.add_argument("--key", required=True); d.add_argument("--file", required=True)
    d.add_argument("--ts", type=int, required=True); d.add_argument("--companion"); d.add_argument("--shared", action="store_true")
    r = sub.add_parser("restore"); r.add_argument("--key", required=True)
    sub.add_parser("pcs")
    args = p.parse_args()
    cfg = read_config(require_id=args.cmd != "login")
    {"login": cmd_login, "find": cmd_find, "delete": cmd_delete, "restore": cmd_restore, "pcs": cmd_pcs}[args.cmd](args, cfg)


if __name__ == "__main__":
    main()
