# 词鲸背单词 trusted server

This folder defines the trusted-service boundary for 词鲸背单词. The current learning APIs run as Supabase Edge Functions under `supabase/functions/`; this Flask service supplies deployment health/readiness endpoints and is the home for future privileged jobs that cannot run in a mobile client.

Production secrets belong in the hosting platform's environment, never in Git or the iOS bundle.

```bash
cp .env.example .env
# 编辑根目录 .env
python3 -m venv server/venv
source server/venv/bin/activate
python -m pip install -r server/requirements.txt
cd server
python -m flask --app app run --host 0.0.0.0 --port 8000
```

服务只读取仓库根目录 `.env`；部署容器时用托管平台或 `docker run --env-file .env` 注入同一组变量。运行测试：`python3 -m unittest discover -s server -p 'test_*.py'`。
