# CiJing · 词鲸背单词

<p align="center">
  <img src="client/CiJing/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="112" alt="CiJing app icon">
</p>

<p align="center">
  Turn words found in real reading into a personal vocabulary library, graded AI stories, and a spaced-review routine.
</p>

<p align="center">
  <a href="README_zh.md">简体中文</a> ·
  <a href="CONTRIBUTING.md">Contributing</a> ·
  <a href="supabase/README.md">Supabase</a> ·
  <a href="server/README.md">Trusted server</a> ·
  <a href="docs/privacy-policy.md">Privacy policy</a>
</p>

<p align="center">
  <img alt="iOS 17+" src="https://img.shields.io/badge/iOS-17%2B-6f49cc">
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-f09b62">
  <img alt="Supabase" src="https://img.shields.io/badge/backend-Supabase-3ecf8e">
  <img alt="license MIT" src="https://img.shields.io/badge/license-MIT-7252cc">
</p>

## Product tour

CiJing has four focused top-level areas. Home brings the daily plan, accumulated progress, persistent reading history, and real learning entry points together in one glance.

<p align="center">
  <img src="docs/assets/screenshots/home.png" width="330" alt="CiJing home with a completed plan, learning totals, saved readings, and study entry points">
</p>

### Four top-level areas

<table>
  <tr>
    <td align="center"><strong>Home</strong><br><sub>Daily plan, persistent reading history, and practice entry points</sub></td>
    <td align="center"><strong>Library</strong><br><sub>Learning states, strength, due dates, and contextual vocabulary</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/home.png" width="310" alt="CiJing home screen"></td>
    <td align="center"><img src="docs/assets/screenshots/library.png" width="310" alt="CiJing word library"></td>
  </tr>
  <tr>
    <td align="center"><strong>Lookup</strong><br><sub>Definitions, pronunciation, examples, and one-tap saving</sub></td>
    <td align="center"><strong>Settings</strong><br><sub>Learning preferences, privacy controls, cache, and account</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/lookup.png" width="310" alt="CiJing word lookup"></td>
    <td align="center"><img src="docs/assets/screenshots/settings.png" width="310" alt="CiJing settings"></td>
  </tr>
</table>

### The complete learning loop

The top-level navigation stays simple, while each reading opens a focused sequence: choose target words, read with optional translations, practise retrieval, shadow sentence by sentence, review progress, and resume saved readings after relaunch.

<table>
  <tr>
    <td align="center"><strong>1 · Choose</strong><br><sub>Theme, style, level, and target words</sub></td>
    <td align="center"><strong>2 · Read</strong><br><sub>Graded bilingual story with highlighted words</sub></td>
    <td align="center"><strong>3 · Practise</strong><br><sub>Meaning, context, spelling, and recall</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/reading-setup.jpg" width="220" alt="Choose reading settings and target words"></td>
    <td align="center"><img src="docs/assets/screenshots/reading.jpg" width="220" alt="Read a bilingual AI story"></td>
    <td align="center"><img src="docs/assets/screenshots/practice.jpg" width="220" alt="Complete reading-based practice"></td>
  </tr>
  <tr>
    <td align="center"><strong>4 · Shadow</strong><br><sub>Listen, speak, and compare sentence by sentence</sub></td>
    <td align="center"><strong>5 · Improve</strong><br><sub>Activity, vocabulary states, and weak words</sub></td>
    <td align="center"><strong>6 · Resume</strong><br><sub>Continue any saved reading after relaunch</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/screenshots/shadowing.jpg" width="220" alt="Sentence shadowing practice"></td>
    <td align="center"><img src="docs/assets/screenshots/progress.jpg" width="220" alt="Learning progress dashboard"></td>
    <td align="center"><img src="docs/assets/screenshots/reading.jpg" width="220" alt="Resume a saved reading after relaunch"></td>
  </tr>
</table>

## What it does

- Captures words and source context from a Chrome Manifest V3 extension.
- Keeps a private, user-scoped word library with notes and learning states.
- Generates coherent bilingual readings from weak, due, and new words.
- Persists every generated reading to `reading_sessions`, so history survives relaunches and sign-ins.
- Schedules review with strength, ease factor, interval, lapse, and due-date signals.
- Provides system pronunciation, shadowing, and short reading-based exercises.
- Protects all user data with Supabase Row Level Security.
- Follows the system appearance before sign-in and for unset accounts; signed-in appearance and local learning switches are isolated by user UUID, and the App Icon includes light/dark system variants.
- Requires email verification for new accounts and rejects an unexpected session returned directly from sign-up.

## Repository layout

```text
.
├── client/      # SwiftUI iOS app
├── extension/   # Chrome extension for contextual lookup and saving
├── supabase/    # PostgreSQL migrations, RLS, RPCs, and Edge Functions
├── server/      # Trusted Flask boundary and health checks
├── scripts/     # Configuration, audit, and smoke-test utilities
├── docs/        # Public policies, developer guides, model notes, and screenshots
└── website/     # Privacy policy and support pages for public hosting
```

## Architecture and security

```text
iOS app ─────┐
             ├─ Supabase Auth / PostgREST ── PostgreSQL + RLS + RPC
Chrome ──────┘                    └────────── Edge Functions ── OpenRouter / Qwen

Physical iPhone ── local Flask integration gateway ── hosted Supabase
Flask server ── trusted health and operations boundary
```

The iOS app and extension share a Supabase account and user-scoped learning data. Every business table has Row Level Security, and database functions execute in the authenticated user's scope. During physical-device testing, iOS Auth, PostgREST, and Edge Functions requests pass through the local Flask gateway before reaching hosted Supabase; the Chrome extension continues to call hosted Supabase directly. The gateway preserves the user's access token and RLS boundary and never injects a server secret into client requests.

The root `.env` is the only local configuration source. Generated iOS and extension configuration is ignored by Git. Client bundles contain only the Supabase URL and publishable key; Supabase secret keys and the OpenRouter API key stay in trusted runtimes. See [Supabase architecture and operations](supabase/README.md) and the [trusted server guide](server/README.md) for component details.

## Quick start

Requirements: macOS, Xcode 16 or newer, Node.js 20+, Docker Desktop, and Chrome. The repository wrapper downloads and caches its pinned Supabase CLI version on first use.

```bash
cp .env.example .env
# Fill the environment values in .env
make config

./scripts/supabase.sh start
./scripts/supabase.sh db reset
make functions
```

Open `client/CiJing.xcodeproj`, select the `CiJing` scheme and an iOS 17+ simulator, then run. Load `extension/` as an unpacked extension from `chrome://extensions`.

Configuration, database, Edge Function, and production instructions live in [supabase/README.md](supabase/README.md). Contribution workflow and physical-device troubleshooting live in [CONTRIBUTING.md](CONTRIBUTING.md).

## Physical-device and release quick reference

Once the iPhone has a device-integration build generated with `make device-config` and rebuilt in Xcode, routine local testing only requires this command from the repository root:

```bash
make server-start
```

Keep that terminal running and keep the iPhone and Mac on the same LAN. The device uses the Mac's Bonjour `.local` hostname, so a Wi-Fi IP change does not require regenerating configuration. For the first device setup, after switching back from release configuration, or after generated files were cleaned, run `make device-config` first and rebuild/reinstall the app in Xcode; starting Flask alone cannot change the URL embedded in an installed app.

Before creating an Archive, TestFlight build, or App Store build, verify that `SUPABASE_URL` in the root `.env` is the hosted production HTTPS URL, then run:

```bash
make config
make config-check
```

`make device-config` never changes the root `.env`, so `make config` restores the iOS client to the hosted URL from `.env`; `make config-check` verifies that generated files match it. Rebuild the Archive after both commands succeed—do not reuse a local device build that points to Flask. The release app does not require the local Flask server.

## Verification

```bash
make config-check
make extension-test
make server-test
make ios-build
```

With Supabase running, `make smoke` verifies the cross-client API flow. Production environments can use `make production-audit` and `make production-smoke` after deployment.

## Documentation

- [Supabase architecture, local development, and production operations](supabase/README.md)
- [Database migration guide](docs/supabase-migration-guide.md) and [Qwen3.6 Flash integration](docs/qwen/qwen3.6-flash.md)
- [Trusted Flask server](server/README.md) and [public website](website/README.md)
- [Privacy policy](docs/privacy-policy.md), [terms of service](docs/terms-of-service.md), and [support](docs/support.md)

## Contributing and security

Please read [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before opening a contribution. Report vulnerabilities privately by following [SECURITY.md](SECURITY.md), not through a public issue.

This project is available under the [MIT License](LICENSE).
