"""Black-box tests for probe_server using the real HTTP server (stdlib only)."""

import http.client
import threading
import unittest
from http.server import ThreadingHTTPServer

from probe_server import HEALTH_BODY, HEALTH_PATH, ProbeHandler


class ProbeServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), ProbeHandler)
        cls.port = cls.server.server_address[1]
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def request(self, method: str, path: str, body: bytes | None = None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            conn.request(method, path, body=body)
            resp = conn.getresponse()
            return resp.status, dict(resp.getheaders()), resp.read()
        finally:
            conn.close()

    def test_get_health(self) -> None:
        status, headers, body = self.request("GET", HEALTH_PATH)
        self.assertEqual(status, 200)
        self.assertEqual(body, HEALTH_BODY)
        self.assertEqual(headers.get("Content-Type"), "text/plain")
        self.assertEqual(headers.get("Content-Length"), str(len(HEALTH_BODY)))

    def test_get_health_query(self) -> None:
        status, _, body = self.request("GET", HEALTH_PATH + "?x=1")
        self.assertEqual(status, 200)
        self.assertEqual(body, HEALTH_BODY)

    def test_head_health(self) -> None:
        status, headers, body = self.request("HEAD", HEALTH_PATH)
        self.assertEqual(status, 200)
        self.assertEqual(body, b"")
        self.assertEqual(headers.get("Content-Type"), "text/plain")
        self.assertEqual(headers.get("Content-Length"), str(len(HEALTH_BODY)))

    def test_post_health_empty(self) -> None:
        status, _, body = self.request("POST", HEALTH_PATH)
        self.assertEqual(status, 200)
        self.assertEqual(body, HEALTH_BODY)

    def test_post_health_with_body(self) -> None:
        status, _, body = self.request("POST", HEALTH_PATH, body=b"x=1")
        self.assertEqual(status, 200)
        self.assertEqual(body, HEALTH_BODY)

    def test_unknown_paths_404(self) -> None:
        for method in ("GET", "HEAD", "POST"):
            status, _, _ = self.request(method, "/other")
            self.assertEqual(status, 404, method)

    def test_no_501(self) -> None:
        for method, path in (
            ("GET", HEALTH_PATH),
            ("HEAD", HEALTH_PATH),
            ("POST", HEALTH_PATH),
        ):
            status, _, _ = self.request(method, path)
            self.assertNotEqual(status, 501, f"{method} {path}")


if __name__ == "__main__":
    unittest.main()
