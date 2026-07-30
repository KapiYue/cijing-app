import os
import unittest
from email.message import Message
from unittest.mock import patch

from app import create_app


class FakeUpstreamResponse:
    def __init__(self, body=b'{}', status=200, headers=None):
        self.status = status
        self._body = body
        self.headers = Message()
        for name, value in (headers or {"Content-Type": "application/json"}).items():
            self.headers[name] = value

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


class ServerTestCase(unittest.TestCase):
    def setUp(self):
        self.client = create_app().test_client()

    def test_health_check(self):
        response = self.client.get("/healthz")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["status"], "ok")

    @patch.dict(os.environ, {}, clear=True)
    def test_readiness_requires_supabase_environment(self):
        response = self.client.get("/readyz")
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.get_json()["error"], "SUPABASE_ENV_MISSING")

    @patch.dict(os.environ, {"SUPABASE_URL": "https://project.supabase.co"}, clear=True)
    @patch("app.urlrequest.urlopen")
    def test_proxy_forwards_auth_request_without_server_secret(self, urlopen):
        urlopen.return_value = FakeUpstreamResponse(
            body=b'{"access_token":"session"}',
            headers={"Content-Type": "application/json", "X-Upstream": "ok"},
        )

        response = self.client.post(
            "/auth/v1/token?grant_type=password",
            data=b'{"email":"review@example.com","password":"secret"}',
            headers={
                "apikey": "public-key",
                "Authorization": "Bearer user-token",
                "Content-Type": "application/json",
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["access_token"], "session")
        self.assertEqual(response.headers["X-Upstream"], "ok")
        upstream_request = urlopen.call_args.args[0]
        self.assertEqual(
            upstream_request.full_url,
            "https://project.supabase.co/auth/v1/token?grant_type=password",
        )
        self.assertEqual(upstream_request.get_method(), "POST")
        self.assertEqual(upstream_request.data, b'{"email":"review@example.com","password":"secret"}')
        self.assertEqual(upstream_request.get_header("Apikey"), "public-key")
        self.assertEqual(upstream_request.get_header("Authorization"), "Bearer user-token")

    @patch.dict(os.environ, {}, clear=True)
    def test_proxy_requires_upstream_environment(self):
        response = self.client.get("/rest/v1/profiles")
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.get_json()["error"], "SUPABASE_ENV_MISSING")


if __name__ == "__main__":
    unittest.main()
