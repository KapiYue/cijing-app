import os
import unittest
from unittest.mock import patch

from app import create_app


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


if __name__ == "__main__":
    unittest.main()

