import os
from pathlib import Path
from urllib import error, request

from flask import Flask, jsonify


def load_local_environment() -> None:
    """Load the repository's single local .env without adding a dependency."""
    env_path = Path(__file__).resolve().parents[1] / ".env"
    if not env_path.exists():
        return
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        quote_pairs = (("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’"))
        if len(value) >= 2 and any(value.startswith(opening) and value.endswith(closing) for opening, closing in quote_pairs):
            value = value[1:-1]
        os.environ.setdefault(key.strip(), value)


load_local_environment()


def create_app() -> Flask:
    app = Flask(__name__)

    @app.get("/")
    @app.get("/healthz")
    def health_check():
        return jsonify({"service": "cijing-server", "status": "ok"})

    @app.get("/readyz")
    def readiness_check():
        """Verify that the trusted runtime can reach the production Supabase API."""
        supabase_url = os.getenv("SUPABASE_URL", "").rstrip("/")
        secret_key = os.getenv("SUPABASE_SECRET_KEY", "")
        if not supabase_url or not secret_key:
            return jsonify({"status": "not_ready", "error": "SUPABASE_ENV_MISSING"}), 503

        probe = request.Request(
            f"{supabase_url}/rest/v1/",
            headers={"apikey": secret_key, "Authorization": f"Bearer {secret_key}"},
            method="GET",
        )
        try:
            with request.urlopen(probe, timeout=5) as response:
                reachable = 200 <= response.status < 500
        except error.HTTPError as exc:
            reachable = 200 <= exc.code < 500
        except (error.URLError, TimeoutError):
            reachable = False

        if not reachable:
            return jsonify({"status": "not_ready", "error": "SUPABASE_UNREACHABLE"}), 503
        return jsonify({"status": "ready"})

    return app


app = create_app()
