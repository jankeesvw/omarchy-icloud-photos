import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bin"))

from icloud_helper import (  # noqa: E402
    PHOTOS_PCS_COOKIES,
    acquire_photos_pcs,
    classify_icloudpd_log,
    pcs_required_from_webservices,
)


class PcsRequiredTests(unittest.TestCase):
    def test_photos_flag(self):
        self.assertTrue(pcs_required_from_webservices({"photos": {"pcsRequired": True}}))

    def test_ckdatabasews_flag(self):
        self.assertTrue(pcs_required_from_webservices({"ckdatabasews": {"pcsRequired": True}}))

    def test_absent_or_false(self):
        self.assertFalse(pcs_required_from_webservices({}))
        self.assertFalse(pcs_required_from_webservices({"photos": {"pcsRequired": False}}))


class AcquirePhotosPcsTests(unittest.TestCase):
    def test_already_has_cookies(self):
        calls = []
        result = acquire_photos_pcs(
            request_fn=lambda: calls.append("request") or {"status": "success"},
            cookie_names_fn=lambda: set(PHOTOS_PCS_COOKIES),
            sleep_fn=lambda _: calls.append("sleep"),
            attempts=3,
            interval=0,
        )
        self.assertEqual(result, "already")
        self.assertEqual(calls, [])

    def test_acquires_after_device_approval(self):
        names = set()
        payloads = [
            {"status": "failure", "message": "Waiting for device consent"},
            {"status": "success", "message": "Cookies attached."},
        ]
        slept = []

        def request():
            payload = payloads.pop(0)
            if payload["status"] == "success":
                names.update(PHOTOS_PCS_COOKIES)
            return payload

        waiting = []
        result = acquire_photos_pcs(
            request_fn=request,
            cookie_names_fn=lambda: names,
            on_waiting=lambda: waiting.append(True),
            sleep_fn=lambda n: slept.append(n),
            attempts=5,
            interval=10,
        )
        self.assertEqual(result, "acquired")
        self.assertEqual(waiting, [True])
        self.assertEqual(slept, [10])

    def test_success_without_cookies_keeps_polling(self):
        requests = []
        result = acquire_photos_pcs(
            request_fn=lambda: requests.append("request") or {"status": "success", "message": "Cookies attached."},
            cookie_names_fn=lambda: set(),
            sleep_fn=lambda _: None,
            attempts=3,
            interval=1,
        )
        self.assertEqual(result, "timeout")
        self.assertEqual(len(requests), 3)

    def test_timeout(self):
        requests = []
        slept = []
        result = acquire_photos_pcs(
            request_fn=lambda: requests.append("request") or {"status": "failure", "message": "Waiting"},
            cookie_names_fn=lambda: set(),
            sleep_fn=lambda n: slept.append(n),
            attempts=2,
            interval=1,
        )
        self.assertEqual(result, "timeout")
        self.assertEqual(len(requests), 2)
        self.assertEqual(slept, [1])


class ClassifyIcloudpdLogTests(unittest.TestCase):
    def test_private_db_is_pcs_not_password(self):
        log = "ERROR    private db access disabled for this account. (ACCESS_DENIED)\n"
        self.assertEqual(classify_icloudpd_log(log), "pcs-required")

    def test_421_is_full_sign_in(self):
        log = "ERROR    Authentication required for Account. (421)\n"
        self.assertEqual(classify_icloudpd_log(log), "auth-required")

    def test_empty_is_none(self):
        self.assertIsNone(classify_icloudpd_log("INFO     Processing user: x\n"))


if __name__ == "__main__":
    unittest.main()
