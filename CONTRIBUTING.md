# Contributing to CiJing

Thank you for helping improve CiJing. Contributions that make language learning clearer, safer, and more reliable are welcome.

## Before you start

1. Search existing issues and pull requests to avoid duplicate work.
2. Open an issue before a large product, schema, or architecture change.
3. Never commit `.env`, service-role keys, provider tokens, real user data, or generated client configuration.
4. Follow the [Code of Conduct](CODE_OF_CONDUCT.md) and report security problems through [SECURITY.md](SECURITY.md).

## Development workflow

1. Fork the repository and create a focused branch from `main`.
2. Copy `.env.example` to `.env`, fill local values, and run `make config`.
3. Keep changes scoped and update relevant documentation or migrations.
4. Add or update tests for behavior changes.
5. Run the verification suite before opening a pull request:

```bash
make config-check
make extension-test
make server-test
make ios-build
```

For database or Edge Function changes, also reset a local Supabase stack and run the smoke test:

```bash
./scripts/supabase.sh db reset
make functions
make smoke
```

## Pull requests

- Explain the user-visible outcome and the reason for the change.
- List verification performed and any known limitations.
- Include before/after screenshots for visual changes.
- Keep database migrations additive and safe for existing user data.
- Do not mix unrelated formatting or refactors into the same pull request.

By contributing, you agree that your contribution is licensed under the repository's [MIT License](LICENSE).
