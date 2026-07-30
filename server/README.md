# 词鲸背单词 trusted server

This folder defines the trusted-service boundary for 词鲸背单词. The learning APIs run in hosted Supabase, while the local Flask process provides a stable physical-device integration gateway and health/readiness checks.

During pre-release physical-device testing the request path is:

```text
iOS ── Mac Flask :8000 ── hosted Supabase Auth, PostgREST and Edge Functions

Chrome extension ───────── hosted Supabase directly
```

`GET /` and `GET /healthz` report process health without contacting dependencies. `GET /readyz` uses the server-only Supabase key to check whether the REST endpoint is reachable; it never returns the key or upstream response body. `/auth/v1/*`, `/rest/v1/*`, and `/functions/v1/*` transparently forward the client's publishable key and user session to hosted Supabase. The proxy never replaces them with the server secret, so Supabase Auth and RLS remain authoritative.

## Local development

Production secrets belong in the hosting platform's environment, never in Git, logs, or a client bundle. For local development, the service reads only the repository-root `.env`.

```bash
cp .env.example .env
# 编辑根目录 .env
python3 -m venv server/venv
source server/venv/bin/activate
python -m pip install -r server/requirements.txt
cd server
python -m flask --app app run --host 0.0.0.0 --port 8000
```

From the repository root, `make server-start` is the equivalent start command. Then run `make device-config` once before rebuilding the iOS app. It keeps `.env` pointed at hosted Supabase, leaves the Chrome extension on the hosted URL, and points only the iOS build at the Mac's Bonjour hostname on port 8000.

Required variables:

| Variable | Purpose | Secret |
| --- | --- | --- |
| `SUPABASE_URL` | Hosted Supabase REST base URL | No |
| `SUPABASE_SECRET_KEY` | Readiness probe and future privileged operations | Yes |
| `PORT` | Container listening port | No |

Run tests from the repository root:

```bash
make server-test
# or
python3 -m unittest discover -s server -p 'test_*.py'
```

## Container and production

Build with [`server/Dockerfile`](Dockerfile) and inject variables using the hosting platform's secret/environment settings. A local container can use `docker run --env-file .env`; do not copy `.env` into the image.

The container starts Gunicorn and binds to `PORT`. Configure the platform probes as follows:

- liveness: `/healthz`;
- readiness: `/readyz`;
- do not expose environment variables or upstream authorization errors in public responses.

After deployment, verify both endpoints from the same network path used by the platform. A `503` from `/readyz` means the process is alive but the Supabase variables are missing or the upstream API is unreachable. Rotate a leaked secret in Supabase and the hosting platform immediately; changing client configuration is neither required nor sufficient.

Database, Edge Function, Auth, client-release, and production-audit steps are documented in [`supabase/README.md`](../supabase/README.md).
