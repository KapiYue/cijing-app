# 词鲸背单词 trusted server

This folder defines the trusted-service boundary for 词鲸背单词. The current learning APIs run as Supabase Edge Functions under `supabase/functions/`; this Flask service supplies deployment health/readiness endpoints and is the home for future privileged jobs that cannot run in a mobile client.

It is deliberately outside the current iOS/extension request path:

```text
iOS / Chrome ── Supabase Auth, PostgREST and Edge Functions

operations ──── Flask /healthz and /readyz ── trusted Supabase probe
```

`GET /` and `GET /healthz` report process health without contacting dependencies. `GET /readyz` uses the server-only Supabase key to check whether the REST endpoint is reachable; it never returns the key or upstream response body. Future privileged jobs belong here only when they cannot safely run in a user-scoped Edge Function or client.

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
