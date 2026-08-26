# Contributing to CiJing

Thank you for helping improve CiJing. Contributions that make language learning clearer, safer, and more reliable are welcome.

## Before you start

1. Search existing issues and pull requests to avoid duplicate work.
2. Open an issue before a large product, schema, or architecture change.
3. Never commit `.env`, service-role keys, provider tokens, real user data, or generated client configuration.
4. Follow the [Code of Conduct](CODE_OF_CONDUCT.md) and report security problems through [SECURITY.md](SECURITY.md).

Local development requires macOS, Xcode 16+, Node.js 20+, Docker Desktop, and Chrome. The repository wrapper downloads and caches the pinned Supabase CLI, so a separate global installation is optional.

## Development workflow

1. Fork the repository and create a focused branch from `main`.
2. Copy `.env.example` to `.env`, fill local values, and run `make config`. The root `.env` is the only local configuration source; generated Swift and JavaScript configuration must remain untracked.
3. Keep changes scoped and update relevant documentation or migrations.
4. Add or update tests for behavior changes.
5. Run the verification suite before opening a pull request:

```bash
make config-check
make extension-test
make server-test
make ios-build
```

Open `client/CiJing.xcodeproj`, select the `CiJing` scheme and an iOS 17+ simulator, and run the app. Load `extension/` from `chrome://extensions` with Developer mode and “Load unpacked”; refresh it there after JavaScript or HTML changes. Use the same email account in both clients to exercise synchronization. Microphone and speech-recognition permission is requested only when starting shadowing.

### Physical-device configuration

An iPhone's `127.0.0.1` points to the phone, not the development Mac. For production-data integration testing, start Flask on `0.0.0.0:8000`, keep both devices on the same LAN, and run:

```bash
make server-start
make device-config
```

The command reads the Mac's Bonjour hostname and regenerates only the iOS client URL. `.env` and the Chrome extension remain pointed at hosted Supabase, so changing Wi-Fi IP addresses does not require editing configuration. Override the host only when Bonjour is unavailable:

```bash
CIJING_LOCAL_SERVER_HOST=192.168.1.20 make device-config
```

You can override the Flask port when necessary:

```bash
CIJING_LOCAL_SERVER_PORT=8080 make device-config
```

Ensure the macOS firewall permits the Flask port. Before an Archive, TestFlight, or App Store build, run `make config` and `make config-check` so the iOS client returns to the production HTTPS URL and does not ship a local gateway address.

For database or Edge Function changes, also reset a local Supabase stack and run the smoke test:

```bash
./scripts/supabase.sh db reset
make functions
make smoke
```

`make smoke` verifies the cross-client API path without a paid model call (it needs `SUPABASE_SECRET_KEY` in `.env`, because signup requires email confirmation and the test confirms its own throwaway user). To exercise one real OpenRouter request, use `node scripts/smoke-test.mjs --ai`. See [supabase/README.md](supabase/README.md) for local services and deployment, [the migration guide](docs/supabase-migration-guide.md) for schema changes, and [the Qwen integration note](docs/qwen/qwen3.7-flash.md) for the AI response contract.

## Pull requests

- Explain the user-visible outcome and the reason for the change.
- List verification performed and any known limitations.
- Include before/after screenshots for visual changes.
- Keep database migrations additive and safe for existing user data.
- Do not mix unrelated formatting or refactors into the same pull request.

By contributing, you agree that your contribution is licensed under the repository's [MIT License](LICENSE).
