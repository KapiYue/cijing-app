# CiJing · 词鲸背单词

<p align="center">
  <img src="client/CiJing/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="112" alt="CiJing app icon">
</p>

<p align="center">
  Turn words found in real reading into a personal vocabulary library, graded AI stories, and a spaced-review routine.
</p>

<p align="center">
  <a href="README_zh.md">简体中文</a> ·
  <a href="docs/DEVELOPMENT.md">Development</a> ·
  <a href="docs/ARCHITECTURE.md">Architecture</a> ·
  <a href="docs/PRODUCTION.md">Production</a> ·
  <a href="docs/APP_STORE_CHECKLIST_zh.md">App Store checklist</a>
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
  <img src="docs/assets/app-store-connect/zh-Hans/iphone-6.5/01-home.jpg" width="330" alt="CiJing home with a completed plan, learning totals, saved readings, and study entry points">
</p>

### Four top-level areas

<table>
  <tr>
    <td align="center"><strong>Home</strong><br><sub>Daily plan, persistent reading history, and practice entry points</sub></td>
    <td align="center"><strong>Library</strong><br><sub>Learning states, strength, due dates, and contextual vocabulary</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/app-store-connect/zh-Hans/iphone-6.5/01-home.jpg" width="310" alt="CiJing home screen"></td>
    <td align="center"><img src="docs/assets/app-store-connect/zh-Hans/iphone-6.5/02-library.jpg" width="310" alt="CiJing word library"></td>
  </tr>
  <tr>
    <td align="center"><strong>Lookup</strong><br><sub>Definitions, pronunciation, examples, and one-tap saving</sub></td>
    <td align="center"><strong>Settings</strong><br><sub>Learning preferences, privacy controls, cache, and account</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/app-store-connect/zh-Hans/iphone-6.5/03-lookup.jpg" width="310" alt="CiJing word lookup"></td>
    <td align="center"><img src="docs/assets/app-store-connect/zh-Hans/iphone-6.5/04-settings.jpg" width="310" alt="CiJing settings"></td>
  </tr>
</table>

### The complete learning loop

The top-level navigation stays simple, while each reading opens a focused sequence: choose target words, read with optional translations, practise retrieval, shadow sentence by sentence, and review progress.

<table>
  <tr>
    <td align="center"><strong>1 · Choose</strong><br><sub>Theme, style, level, and target words</sub></td>
    <td align="center"><strong>2 · Read</strong><br><sub>Graded bilingual story with highlighted words</sub></td>
    <td align="center"><strong>3 · Practise</strong><br><sub>Meaning, context, spelling, and recall</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/app-store-connect/zh-Hans/iphone-6.5/05-reading-setup.jpg" width="220" alt="Choose reading settings and target words"></td>
    <td align="center"><img src="docs/assets/app-store-connect/zh-Hans/iphone-6.5/06-reading.jpg" width="220" alt="Read a bilingual AI story"></td>
    <td align="center"><img src="docs/assets/app-store-connect/zh-Hans/iphone-6.5/07-practice.jpg" width="220" alt="Complete reading-based practice"></td>
  </tr>
  <tr>
    <td align="center"><strong>4 · Shadow</strong><br><sub>Listen, speak, and compare sentence by sentence</sub></td>
    <td align="center"><strong>5 · Improve</strong><br><sub>Activity, vocabulary states, and weak words</sub></td>
    <td align="center"><strong>One continuous loop</strong><br><sub>Every saved reading remains available after relaunch</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/assets/app-store-connect/zh-Hans/iphone-6.5/08-shadowing.jpg" width="220" alt="Sentence shadowing practice"></td>
    <td align="center"><img src="docs/assets/app-store-connect/zh-Hans/iphone-6.5/09-progress.jpg" width="220" alt="Learning progress dashboard"></td>
    <td align="center">Save → Read → Practise → Revisit</td>
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

## Repository layout

```text
.
├── client/      # SwiftUI iOS app
├── extension/   # Chrome extension for contextual lookup and saving
├── supabase/    # PostgreSQL migrations, RLS, RPCs, and Edge Functions
├── server/      # Trusted Flask boundary and health checks
├── scripts/     # Configuration, audit, and smoke-test utilities
├── docs/        # Development, architecture, production, and store assets
└── website/     # Privacy policy and support pages for public hosting
```

The iOS app and extension talk to Supabase Auth and PostgREST. Authenticated Edge Functions call the configured OpenRouter model for dictionary explanations and graded readings. Server-only and AI provider keys are never embedded in client bundles.

## Quick start

Requirements: macOS, Xcode 16 or newer, Node.js 20+, Docker Desktop, and Chrome.

```bash
cp .env.example .env
# Fill the environment values in .env
make config

./scripts/supabase.sh start
./scripts/supabase.sh db reset
make functions
```

Open `client/CiJing.xcodeproj`, select the `CiJing` scheme and an iOS 17+ simulator, then run. Load `extension/` as an unpacked extension from `chrome://extensions`.

## Verification

```bash
make config-check
make extension-test
make server-test
make ios-build
```

With Supabase running, `make smoke` verifies the cross-client API flow. Production environments can use `make production-audit` and `make production-smoke` after deployment.

## Contributing and security

Please read [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before opening a contribution. Report vulnerabilities privately by following [SECURITY.md](SECURITY.md), not through a public issue.

This project is available under the [MIT License](LICENSE).
