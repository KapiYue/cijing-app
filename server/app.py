import os
from pathlib import Path
from urllib import error, request as urlrequest

from flask import Flask, Response, jsonify, request as flask_request


PROXY_METHODS = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
HOP_BY_HOP_HEADERS = {
    "connection",
    "content-length",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}


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
        # The repository .env is the single source of truth for local runs.
        # Hosted deployments do not contain this file and keep using injected variables.
        os.environ[key.strip()] = value


load_local_environment()


def create_app() -> Flask:
    app = Flask(__name__)

    def upstream_supabase_url() -> str:
        return os.getenv("SUPABASE_URL", "").rstrip("/")

    def proxy_to_supabase(upstream_path: str) -> Response:
        supabase_url = upstream_supabase_url()
        if not supabase_url:
            return jsonify({"status": "not_ready", "error": "SUPABASE_ENV_MISSING"}), 503

        query = flask_request.query_string.decode("latin-1")
        upstream_url = f"{supabase_url}/{upstream_path}"
        if query:
            upstream_url += f"?{query}"

        headers = {
            name: value
            for name, value in flask_request.headers.items()
            if name.lower() not in HOP_BY_HOP_HEADERS and name.lower() != "host"
        }
        body = flask_request.get_data(cache=False) or None
        proxy_request = urlrequest.Request(
            upstream_url,
            data=body,
            headers=headers,
            method=flask_request.method,
        )

        try:
            upstream_response = urlrequest.urlopen(proxy_request, timeout=45)
            status = upstream_response.status
            response_body = upstream_response.read()
            response_headers = upstream_response.headers
        except error.HTTPError as exc:
            status = exc.code
            response_body = exc.read()
            response_headers = exc.headers
        except (error.URLError, TimeoutError):
            return jsonify({"status": "bad_gateway", "error": "SUPABASE_UNREACHABLE"}), 502

        response = Response(response_body, status=status)
        for name, value in response_headers.items():
            if name.lower() not in HOP_BY_HOP_HEADERS and name.lower() not in {"server", "date"}:
                response.headers[name] = value
        return response

    @app.route("/auth/v1/", defaults={"subpath": ""}, methods=PROXY_METHODS)
    @app.route("/auth/v1/<path:subpath>", methods=PROXY_METHODS)
    def proxy_auth(subpath: str):
        return proxy_to_supabase(f"auth/v1/{subpath}")

    @app.route("/rest/v1/", defaults={"subpath": ""}, methods=PROXY_METHODS)
    @app.route("/rest/v1/<path:subpath>", methods=PROXY_METHODS)
    def proxy_rest(subpath: str):
        return proxy_to_supabase(f"rest/v1/{subpath}")

    @app.route("/functions/v1/", defaults={"subpath": ""}, methods=PROXY_METHODS)
    @app.route("/functions/v1/<path:subpath>", methods=PROXY_METHODS)
    def proxy_functions(subpath: str):
        return proxy_to_supabase(f"functions/v1/{subpath}")

    @app.get("/")
    @app.get("/healthz")
    def health_check():
        return jsonify({"service": "cijing-server", "status": "ok"})

    @app.get("/readyz")
    def readiness_check():
        """Verify that the trusted runtime can reach the production Supabase API."""
        supabase_url = upstream_supabase_url()
        secret_key = os.getenv("SUPABASE_SECRET_KEY", "")
        if not supabase_url or not secret_key:
            return jsonify({"status": "not_ready", "error": "SUPABASE_ENV_MISSING"}), 503

        probe = urlrequest.Request(
            f"{supabase_url}/rest/v1/",
            headers={"apikey": secret_key, "Authorization": f"Bearer {secret_key}"},
            method="GET",
        )
        try:
            with urlrequest.urlopen(probe, timeout=5) as response:
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
