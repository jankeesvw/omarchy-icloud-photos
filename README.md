<p align="center">
  <img src="assets/icon.png" width="96" height="96" alt="">
</p>

<h1 align="center">Omarchy iCloud Photos</h1>

<p align="center">The last month of your iCloud Photos library as a native window on <a href="https://omarchy.org">Omarchy</a>.<br>Browse by day, watch your videos, delete with undo, copy and save. No browser tab, no Apple hardware.</p>

<p align="center">
  <a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square"></a>
  <img alt="Quickshell" src="https://img.shields.io/badge/ui-Quickshell-7aa2f7?style=flat-square">
  <img alt="Omarchy 4+" src="https://img.shields.io/badge/omarchy-4.0%2B-9ece6a?style=flat-square">
  <img alt="sync by icloudpd" src="https://img.shields.io/badge/sync-icloudpd-e0af68?style=flat-square">
</p>

<p align="center">
  <img src="assets/social.gif" width="800" alt="The window scrolling through a week of photos, then opening one">
</p>

<p align="center"><sub>The clip and the screenshots come from the built-in demo mode, so those are Omarchy wallpapers, not anyone's holiday. <a href="assets/social.mp4">MP4 version</a>.</sub></p>

> **Credit where it is due.** The syncing is done by [icloudpd](https://github.com/icloud-photos-downloader/icloud_photos_downloader), the iCloud Photos Downloader by the icloud-photos-downloader project. I did not write it and this repository does not fork it. What you find here is the window, the index, the sign-in and delete helper on top of its pyicloud module, and the glue between them.

## Install

The quickest way is to let your coding agent do it. Paste this into Claude Code, Codex or whatever runs your terminal:

> Install Omarchy iCloud Photos from https://github.com/jankeesvw/omarchy-icloud-photos on this Omarchy machine. Install the pacman packages quickshell, imagemagick, ffmpeg, jq and wl-clipboard if they are missing. Clone the repository into ~/Documents/github.com/jankeesvw/omarchy-icloud-photos and run its install.sh; it needs no root and fetches icloudpd and a Python 3.13 itself. Then start `omarchy-icloud-photos` and tell me it is ready for me to sign in; the sign-in happens inside the window and you never need my password. Do not run icloudpd with `--auto-delete` or `--keep-omarchy-icloud-photos-days`, and do not change the config beyond what install.sh writes.

<details>
<summary>By hand</summary>

```bash
sudo pacman -S --needed quickshell imagemagick ffmpeg jq wl-clipboard
git clone https://github.com/jankeesvw/omarchy-icloud-photos.git ~/Documents/github.com/jankeesvw/omarchy-icloud-photos
~/Documents/github.com/jankeesvw/omarchy-icloud-photos/install.sh
```

The installer links the launcher and the sync script into `~/.local/bin`, adds "Omarchy iCloud Photos" to the app launcher, fetches the icloudpd binary into `~/.local/bin` when it is not installed already, creates a small Python virtualenv for the iCloud helper (a 3.13 from mise when the system Python is newer) and enables the sync timer. Nothing after the pacman line needs root.

Then start `omarchy-icloud-photos`, or pick "Omarchy iCloud Photos" in the launcher, and sign in. Apple ID and password first, then the six-digit code from your phone.
 The first sync takes a few minutes; HDR videos take the longest because each one gets a tone-mapped copy for playback. Run `install.sh` again after a `git pull`; everything is linked, not copied.

</details>

## Why

Apple does not make an iCloud Photos client for Linux, and the web app is a browser tab that forgets who you are every few days. This is the other way round: a small sync script keeps a local copy of your last month of photos and videos, and a Quickshell window shows them the way the Photos app does, newest at the bottom, in whatever Omarchy theme you are running. Everything is a keystroke away and nothing needs a mouse.

![The grid: a week of photos and videos grouped by day, in the Tokyo Night theme](assets/screenshot.jpg)

## What it does

- **Grid by day.** The last month of photos, videos and Live Photos, grouped by day with the newest at the bottom. Thumbnails scale with a slider.
- **Shared Library too.** If your account is in an iCloud Shared Library, its last month is in the same grid, each item with a small person mark top-right, like the Photos app. Delete and undo work there as well, for everyone in the library.
- **Viewer.** Full-window stills, video with a timeline you can scrub, Live Photos that play once when you hover the little circle, like on the phone. `i` shows camera, lens, shutter, ISO, size and location. iPhone videos are HDR and most Linux players show them washed out; here they look right.
- **Delete with undo.** `d` moves an item, or a selection, to iCloud's Recently Deleted, the same 30-day bin the Photos app uses. Undo brings it back, from the toast or with `u`. Nothing here can empty that bin.
- **Copy and save.** `Ctrl+C`, `y`, or right-click → Copy puts the image on the clipboard as PNG from either the grid or the viewer, including for HEIC originals, so browsers can paste it as an image. Multiple selections in the grid copy as a list of files in their original image formats; the viewer copies only the opened image. Right-clicking a selected photo keeps the selection, while right-clicking another photo selects that one. `s` and the Download button save a copy to `~/Downloads` as JPEG or MP4, whatever the original was. Clicking the filename copies its full path.
- **Signs in by itself.** Apple ID, password and the two-factor code go into the window on first run and whenever the session expires. The password is only used to open the session and is never stored.
- **Wallpaper.** `W` makes the current photo the Omarchy background, HEIC included.
- **Stays in sync.** A systemd user timer pulls new items every 30 minutes. An open window picks them up on its own.
- **Follows your theme.** Colours come live from Omarchy's `colors.toml`; switch themes and the window switches with you.

## A look around

Every picture here is the whole window, taken from the demo library.

<table>
<tr>
<td width="50%"><img src="assets/live.jpg" alt="A Live Photo in the viewer, the ring top-left lit while the clip plays"><br><sub>A Live Photo: hover the ring top-left and the clip plays once.</sub></td>
<td width="50%"><img src="assets/details.jpg" alt="The viewer with the details panel open"><br><sub><code>i</code>: camera, lens, focal length, aperture, shutter, ISO, size and location.</sub></td>
</tr>
<tr>
<td><img src="assets/delete.jpg" alt="The delete dialog over the grid"><br><sub><code>d</code> asks first, with the picture in the dialog.</sub></td>
<td><img src="assets/undo.jpg" alt="The grid with the toast offering Undo after a delete"><br><sub>Then it is gone, with an Undo button for twelve seconds and <code>u</code> after that.</sub></td>
</tr>
<tr>
<td><img src="assets/select.jpg" alt="A range of tiles ticked in the grid"><br><sub>Shift selects a range, ctrl-click or <code>x</code> ticks one more; <code>y</code>, <code>s</code> and <code>d</code> then act on all of them.</sub></td>
<td><img src="assets/keys.jpg" alt="The keyboard overlay"><br><sub><code>?</code> lists every key.</sub></td>
</tr>
<tr>
<td><img src="assets/video.jpg" alt="A video in the viewer with the timeline underneath"><br><sub>Video with a timeline to scrub. HDR from the phone plays with the right colours.</sub></td>
<td><img src="assets/signin.jpg" alt="The sign-in card asking for the verification code"><br><sub>Sign-in lives in the window: Apple ID, password, then the six-digit code.</sub></td>
</tr>
</table>

## Built on

The window is the only new thing here; the plumbing is existing, well-worn tools by other people.

- **[icloudpd](https://github.com/icloud-photos-downloader/icloud_photos_downloader)** does the downloading. It speaks the same private web API as icloud.com, keeps a session in `~/.config/icloudpd` and is used strictly in copy mode.
- **pyicloud**, the module that ships inside icloudpd, handles sign-in with two-factor and the per-asset delete and restore, from a small Python helper in the repository's own virtualenv.
- **bash and jq** build the index: one JSON file listing every item in the range with its thumbnail, preview, video and capture time.
- **ImageMagick** with libheif makes the thumbnails and the JPEG previews of HEIC originals, which Qt cannot decode.
- **ffmpeg** grabs video poster frames and tone-maps HDR videos (HLG and PQ) to SDR H.264 copies for playback, since Qt's player does no tone mapping.
- **[Quickshell](https://quickshell.org)** on Qt 6 renders the window in QML, with QtMultimedia for video.
- **systemd** user units run the sync every 30 minutes at low priority.

## Safety first

The sync can only download. icloudpd runs in its default copy mode, without `--auto-delete` or `--keep-omarchy-icloud-photos-days`, and the local library is never pruned: shrink the range and files simply leave the grid. The one thing that writes to iCloud is `d`, which flips a single asset's `isDeleted` flag, exactly what the Photos app does when you tap the bin. There is no bulk delete and no way to empty Recently Deleted from here. For an item from the Shared Library that is the library's own Recently Deleted, which every participant sees; the dialog says so before you confirm.

It talks to iCloud through the same unofficial web API icloudpd uses. Apple can change that at any time, and Apple shuts the sign-in door for a while after several sign-ins in a short time; when that happens the card says so, and the only cure is to leave it alone for half an hour, since every attempt extends the wait. When something breaks, the window says so.

## Keys

Press `?` in the app for this list.

| Key | Grid | Viewer |
|---|---|---|
| `h` `j` `k` `l`, arrows | move | previous / next |
| `Shift` + move, shift-click | select a range | |
| `Ctrl` + click, `x`, `Ctrl` + `Space` | add or remove one | |
| `Ctrl` + `a` | select all | |
| `Enter`, `Space` | open the viewer | pause or resume a video, play a Live Photo once |
| `←` / `→` | move | seek 5 seconds |
| `d` / `u` | delete, undo | same |
| `Ctrl+C` / `y` | copy image or selected files | copy opened image |
| right-click → Copy | copy image or selected files | copy opened image |
| `Y` | copy path | same |
| `s` | save to `~/Downloads` as JPEG or MP4 | same |
| `o` | open in the default app | same |
| `W` | set as the Omarchy wallpaper | same |
| `r` | sync now | |
| `-` / `+` | smaller, larger thumbnails | |
| `g` / `G` | oldest, newest | |
| `i` | | camera, lens, shutter, ISO, size, location |
| `?` | show the keys | same |
| `Esc`, `q` | clear the selection, quit | back to the grid |

A click selects, a second click on the selected item opens it. Hovering does nothing.

## Configuration

`~/.config/omarchy-icloud-photos/config` is sourced by the sync script.

| Variable | Default | Meaning |
|---|---|---|
| `APPLE_ID` | set by the sign-in card | The account to sync |
| `LIBRARY` | `~/Pictures/iCloud` | Where originals land, as `YYYY/MM/` folders; the Shared Library goes under `shared/` in it |
| `SHARED_LIBRARY` | `auto` | `auto` syncs the Shared Library your account is in, `no` leaves it out, a `SharedSync-…` name from `icloudpd --list-libraries` picks one |
| `COOKIES` | `~/.config/icloudpd` | Where the iCloud session lives |
| `CACHE` | `~/.cache/omarchy-icloud-photos` | Thumbnails, previews, SDR video copies and the index |
| `LAUNCHER_NAME` | `Omarchy iCloud Photos` | What the app is called in the launcher; re-run `install.sh` after changing it |

The window covers the last month. That is a deliberate size: enough to matter, small enough that the grid stays quick and a first sync takes minutes rather than hours. The local library is never pruned, so nothing on disk goes away when the month moves on.

The same session also works from the command line, for a headless box or when you prefer a terminal:

```bash
icloudpd --auth-only --username you@example.com --cookie-directory ~/.config/icloudpd
```

## Demo mode

`omarchy-icloud-photos --demo` starts the window on a stand-in library built from the Omarchy theme backgrounds: photos, portrait crops, a few slow-pan videos and Live Photo pairs, some of them marked as coming from a Shared Library, spread over the last days. It lives under `~/.cache/omarchy-icloud-photos-demo`, apart from your real config and cache, and nothing in it talks to iCloud, so delete and undo can be tried freely. That is what the screenshots are made with. `omarchy-icloud-photos-demo --reset` rebuilds it, and `omarchy-icloud-photos --demo --tour` scrolls through the grid by itself and opens a photo, for recording a clip.

## How it works

`bin/omarchy-icloud-photos-sync` runs icloudpd for the newest items, once for your own library and once more with `--library` for the Shared Library your account is in (looked up with `--list-libraries` once a day and landing under `shared/`), then indexes every file in the library from the last month. Capture time is the file's mtime, which icloudpd sets to the asset's creation date. Each item gets a 400 px thumbnail; HEIC also gets a 2200 px JPEG preview because Qt cannot decode HEIC. A Live Photo's `_HEVC.MOV` companion folds into its still. HDR videos get a tone-mapped H.264 copy for playback; the original stays untouched and is what `o`, `s` and `Y` refer to. The result is `index.json` and `status.json` in the cache; the window watches both.

`bin/icloud_helper.py` is the only code that talks to iCloud beyond downloading: it signs in, and it moves one asset at a time to Recently Deleted or back, in whichever library it came from. The Shared Library sits in the owner's private database next to the personal one and in the shared database of everyone who joined, so the helper looks in both. It runs on the pyicloud module that ships with icloudpd, in the repository's own virtualenv.

```
bin/omarchy-icloud-photos          launcher: quickshell -p ui/shell.qml (--demo, --tour)
bin/omarchy-icloud-photos-sync     download + index, safe to run any time
bin/omarchy-icloud-photos-demo     builds the demo library from the theme backgrounds
bin/omarchy-icloud-photos-info     camera and file details for the viewer's i panel
bin/omarchy-icloud-photos-helper   wrapper that runs icloud_helper.py in .venv
bin/icloud_helper.py       login, and find / delete / restore one asset
ui/shell.qml               window, grid, key handling
ui/Thumb.qml               one grid cell
ui/Viewer.qml              full-window still / video with timeline
ui/ConfirmDelete.qml       the "move to Recently Deleted?" dialog
ui/Login.qml               sign-in card (Apple ID, password, 2FA code)
ui/Help.qml                the ? overlay
ui/Theme.qml               colours from ~/.local/state/omarchy/current/theme/colors.toml
systemd/                   user service + 30 minute timer
install.sh                 links everything into place
```

## Contributing

Issues and pull requests are welcome. Run `omarchy-icloud-photos --demo` to work on the window without an Apple account; the demo library exercises photos, videos and Live Photos. Keep the safety rules: the sync stays in copy mode, and nothing deletes more than the one item the user pointed at.

## License

MIT. icloudpd, Quickshell and the other tools have their own licenses.
