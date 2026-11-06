# CiJing · Learn Words in Context

<p align="center">
  <img src="client/CiJing/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="112" alt="CiJing app icon">
</p>

<p align="center">
  Start with words you meet in real reading, then connect their context, reading, practice, and review into a learning loop that lasts.
</p>

<p align="center">
  <a href="https://apps.apple.com/cn/iphone/search?term=%E8%AF%8D%E9%B2%B8%E8%83%8C%E5%8D%95%E8%AF%8D">Find CiJing on the App Store</a> ·
  <a href="https://chromewebstore.google.com/detail/%E8%AF%8D%E9%B2%B8%E8%83%8C%E5%8D%95%E8%AF%8D/afihhehkmefgcknloikpejfpikcddifn">Install the Chrome extension</a> ·
  <a href="https://github.com/KapiYue/huoci">HuoCi WeChat Mini Program</a> ·
  <a href="README_zh.md">简体中文</a>
</p>

<p align="center">
  <img alt="iOS 17+" src="https://img.shields.io/badge/iOS-17%2B-6f49cc">
  <img alt="Chrome Extension" src="https://img.shields.io/badge/Chrome-Extension-4285F4">
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-f09b62">
  <img alt="Supabase" src="https://img.shields.io/badge/backend-Supabase-3ecf8e">
  <img alt="license MIT" src="https://img.shields.io/badge/license-MIT-7252cc">
</p>

## Product demo

<table>
  <tr>
    <td width="50%" align="center" valign="top">
      <a href="https://youtu.be/H4Yp9_9SJho">
        <img src="https://github.com/user-attachments/assets/26671414-6fac-46d8-a5bd-2a7d5d682154" alt="CiJing: look up and save words, read graded stories, and practise retrieval" width="100%">
      </a>
      <br><br>
      <strong>Full product walkthrough</strong>
      <br>
      <sub>Capture words → AI graded reading → reading practice → spaced review</sub>
      <br><br>
      <a href="https://youtu.be/H4Yp9_9SJho">▶ Watch the YouTube walkthrough</a>
    </td>
    <td width="50%" align="center" valign="top">
      <a href="https://chromewebstore.google.com/detail/%E8%AF%8D%E9%B2%B8%E8%83%8C%E5%8D%95%E8%AF%8D/afihhehkmefgcknloikpejfpikcddifn">
        <img src="https://github.com/user-attachments/assets/f467091f-a881-4a28-8d85-c4e824c1224c" alt="CiJing Chrome extension: double-click a word to look it up and save it with web context" width="100%">
      </a>
      <br><br>
      <strong>CiJing Chrome extension</strong>
      <br>
      <sub>Double-click lookup → preserve sentence and source → save once → continue in CiJing</sub>
      <br><br>
      <a href="https://chromewebstore.google.com/detail/%E8%AF%8D%E9%B2%B8%E8%83%8C%E5%8D%95%E8%AF%8D/afihhehkmefgcknloikpejfpikcddifn">▶ Install from Chrome Web Store</a>
    </td>
  </tr>
</table>

## Why CiJing exists

Vocabulary study is often separated from real reading: looked-up words disappear into search history, their original sentences are forgotten, and saving, practice, and review live in different tools. CiJing connects the meaningful actions that follow meeting a word: understand it in context, save it, bring it into readable content, and meet it again at the right time.

## What it delivers

| CiJing iOS app | CiJing Chrome extension | HuoCi WeChat Mini Program |
| --- | --- | --- |
| Personal vocabulary library, AI graded readings, reading practice, sentence shadowing, and progress. | Double-click lookup in the current web context, pronunciation, and saving a word with its source. | A lighter entry point for daily study in WeChat; search for “活词” to use it. |

The three entry points share core vocabulary data, context, and review foundations, while each keeps screens and learning orchestration designed for its setting.

## Core experience

| 1. Understand in context | 2. Save the source | 3. Bring words into a story | 4. Retain through practice |
| --- | --- | --- | --- |
| Double-click on the web or look up in the app to see definitions, phonetics, pronunciation, and examples. | Save the first sentence, webpage source, and your own notes. | Choose from new, weak, and due words to create a coherent bilingual, graded story. | Complete meaning, contextual cloze, active recall, and spelling tasks; results guide later review. |

<p align="center">
  <img src="docs/assets/screenshots/reading-setup.jpg" width="205" alt="Choose target words and reading settings">
  <img src="docs/assets/screenshots/reading.jpg" width="205" alt="Read a bilingual story">
  <img src="docs/assets/screenshots/practice.jpg" width="205" alt="Complete reading-based practice">
  <img src="docs/assets/screenshots/shadowing.jpg" width="205" alt="Shadow a sentence">
</p>

## Interface and modules

| Home | Library | Lookup | Settings |
| --- | --- | --- | --- |
| Daily plan, accumulated progress, saved readings, and a way back into learning. | Learning states, strength, due dates, and each word's context. | Definitions, pronunciation, examples, and one-tap saving. | Learning preferences, privacy, cache, and account controls. |
| <img src="docs/assets/screenshots/home.png" width="190" alt="CiJing home"> | <img src="docs/assets/screenshots/library.png" width="190" alt="CiJing library"> | <img src="docs/assets/screenshots/lookup.png" width="190" alt="CiJing lookup"> | <img src="docs/assets/screenshots/settings.png" width="190" alt="CiJing settings"> |

## Interoperable across products, without forcing one product shape

[HuoCi](https://github.com/KapiYue/huoci) is CiJing's WeChat Mini Program companion. It shares core vocabulary data, context, and review foundations with CiJing, while keeping its own onboarding, daily learning flow, and product states for the Mini Program.

```text
CiJing iOS app ────────┐
CiJing Chrome extension ┼── Shared account, vocabulary facts, context, and review foundations ── Supabase
HuoCi WeChat Mini Program ┘

Each product owns its own screens, learning queue, product metrics, and interaction rhythm.
```

This lets you collect real words while reading at your computer, study them deeply on iPhone, and use HuoCi as a lighter daily entry point in WeChat.

## Repository layout

```text
.
├── client/      # SwiftUI iOS app
├── extension/   # Published Chrome lookup and saving extension
├── supabase/    # Shared data model, RLS, RPCs, and Edge Functions
├── server/      # Trusted Flask boundary and health checks
├── scripts/     # Configuration, auditing, and automated checks
├── docs/        # Public documentation, screenshots, and demo assets
└── website/     # Privacy policy and support pages
```

The HuoCi Mini Program, cross-product shared types, and Mini Program-specific logic live in the separate [huoci](https://github.com/KapiYue/huoci) repository.

## Run locally

You need macOS, Xcode 16+, Node.js 20+, Docker Desktop, and Chrome. Copy the environment template, generate the client configuration, then start local Supabase:

```bash
cp .env.example .env
# Fill the environment values in .env
make config

./scripts/supabase.sh start
./scripts/supabase.sh db reset
make functions
```

Open `client/CiJing.xcodeproj` in Xcode, select the `CiJing` scheme and an iOS 17+ simulator, then run. For the development extension, open `chrome://extensions`, enable developer mode, and load `extension/` unpacked.

## Verification and developer documentation

```bash
make config-check
make extension-test
make server-test
make ios-build
```

Implementation, database, and release detail lives in the component documentation:

- [Supabase architecture, local development, and production operations](supabase/README.md)
- [Trusted Flask server](server/README.md)
- [Contributing](CONTRIBUTING.md)
- [Privacy policy](docs/privacy-policy.md), [terms](docs/terms-of-service.md), and [support](docs/support.md)

This project is available under the [MIT License](LICENSE). Please report vulnerabilities privately through [SECURITY.md](SECURITY.md).
