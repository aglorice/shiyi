<div align="center">
  <img src="assets/logo/pixel_cat_logo_1024.png" width="120" height="120" alt="拾邑 Logo">

  <h1>拾邑</h1>

  <p><strong>All-in-one campus assistant for Wuyi University</strong></p>

  <p>
    <img src="https://img.shields.io/badge/Flutter-3.35+-02569B?style=flat-square&logo=flutter" alt="Flutter">
    <img src="https://img.shields.io/badge/Dart-3.9+-0175C2?style=flat-square&logo=dart" alt="Dart">
    <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-4CAF50?style=flat-square" alt="Platform">
    <img src="https://img.shields.io/badge/License-MIT-yellow?style=flat-square" alt="License">
  </p>

  <p>
    <a href="#features">Features</a> •
    <a href="#screenshots">Screenshots</a> •
    <a href="#getting-started">Getting Started</a> •
    <a href="#tech-stack">Tech Stack</a> •
    <a href="#project-structure">Project Structure</a>
  </p>

  <p>
    <a href="README_CN.md">中文文档</a>
  </p>
</div>

---

**拾邑** (Shí Yì) is a campus assistant app for students at Wuyi University. It
glues together academic data, campus services and daily utilities into a
single Flutter app.

> 拾取校园点滴，邑你相伴同行。
>
> Both undergraduate and graduate accounts are supported; module endpoints
> route automatically based on the user's program.

## Features

### Auth & Accounts

- **Username + password SSO** — full reverse-engineered CAS flow, password
  AES-encrypted in local secure storage, silent re-login on session expiry
- **Phone + SMS code login** — slider captcha, dynamic code request and login
  POST all reproduced; falls back to manual drag if auto solver fails
- **Slider captcha sheet** — Flutter widget reuses the school's web algorithm,
  including track sampling, AES-signed payload and `safeSecure` extraction
  from the trailing 16 bytes of `smallImage`
- **Real logout** — calls `/authserver/logout` to revoke `CASTGC` server-side,
  clears local session and credential vault

### Academics

- **Class schedule** — week / today views, multi-term picker, custom period
  timing (morning / afternoon / evening + lesson length + long break),
  background image, ICS export with smart week-set detection (single/double
  weeks, gaps)
- **Grades** — per-term breakdown
- **Exams** — time and location
- **Notices** — campus + graduate boards combined
- **School news** — official news feed mirrored locally

### Campus Services

- **Dorm electricity** — live balance, usage chart, recharge history
- **Gym booking** — venue browsing, time slot picking, reservation submission,
  appointment list, kick remote sessions
- **Single sign-on for ehall** — drop-in WebView preloaded with the right
  cookies for any campus app

### Personal center (authserver)

- **Active sessions** — list and kick (kicking yourself logs you out and
  routes back to the login screen)
- **Login / app access / password change logs** — paginated, pull-to-refresh,
  near-bottom auto-load
- **IP geo lookup** — long-press to copy

### Quality of life

- **Hitokoto bubble** — toggleable, pet pixel-art beside it
- **Request log** — every Dio instance writes to a ring-buffered log with
  sensitive fields redacted; visible in settings
- **GitHub mirror manager** — built-in mirrors, custom entries, parallel
  latency probe, single selection used for app updates
- **In-app update** — checks GitHub Releases, streams APK with progress, hands
  off to system installer
- **Storage & cache** — one-tap reset
- **Adaptive layout** — phone bottom nav, wide-screen NavigationRail, desktop
  sidebar; Windows / macOS desktop builds out of the box

### Personalization

- Theme presets, dark / light / system mode
- Font scale (default 90%), compact mode, high contrast
- Schedule background presets and custom image

## Screenshots

| Landing | Home | Schedule | Notice |
| --- | --- | --- | --- |
| ![Landing](docs/screenshots/homepage%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.05.08.png) | ![Home](docs/screenshots/home%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.02.48.png) | ![Schedule](docs/screenshots/course%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.05.36.png) | ![Notice](docs/screenshots/notice%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.05.41.png) |

| Electricity | Services | Exams | Settings |
| --- | --- | --- | --- |
| ![Electricity](docs/screenshots/electric%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.06.17.png) | ![Services](docs/screenshots/service%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.06.23.png) | ![Exams](docs/screenshots/exam%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.07.44.png) | ![Settings](docs/screenshots/setting%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.05.45.png) |

| Gym Booking | Recommendations | Venue Search |
| --- | --- | --- |
| ![Gym](docs/screenshots/order-%20iPhone%2016%20Plus%20-%202026-04-09%20at%2009.24.56.png) | ![Recommendations](docs/screenshots/like%20-%20iPhone%2016%20Plus%20-%202026-04-09%20at%2009.25.20.png) | ![Search](docs/screenshots/search%20-%20iPhone%2016%20Plus%20-%202026-04-09%20at%2009.25.26.png) |

## Getting Started

### Prerequisites

- Flutter SDK >= 3.35.0 (verified on 3.35.6)
- Dart SDK >= 3.9.2
- Android Studio or VS Code
- Android SDK (for Android builds)
- Xcode 16+ (for iOS / macOS, macOS only)

### Install & run

```bash
git clone https://github.com/aglorice/uni_yi.git
cd uni_yi
flutter pub get
flutter run
```

### Build

```bash
flutter build apk --release         # universal APK
flutter build appbundle --release   # Play Store AAB
flutter build ios --release
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

### Regenerate launcher icons

```bash
dart run flutter_launcher_icons
```

Reads `flutter_launcher_icons` config in `pubspec.yaml`, regenerates the
Android adaptive icon set and the iOS AppIcon set.

## Tech Stack

| Category | Technology |
| --- | --- |
| Framework | Flutter 3.35+ / Dart 3.9+ |
| State management | Riverpod 3.x |
| Routing | GoRouter 17.x (refreshListenable triggers redirect re-eval) |
| Networking | Dio + custom logging interceptor with header redaction |
| Local storage | SharedPreferences + FlutterSecureStorage |
| Crypto | encrypt (AES-CBC + PKCS7) |
| WebView | webview_flutter (cookie-shared SSO) |
| Icons | flutter_launcher_icons (iOS squircle + Android adaptive) |
| Architecture | Clean-ish / feature-first; each module ships its own domain / data / presentation |

## Project Structure

```
lib/
├── main.dart                  # entry point
├── app/                       # app-level configuration
│   ├── bootstrap/             # initialization
│   ├── di/                    # dependency injection
│   ├── layout/                # breakpoints
│   ├── router/                # GoRouter
│   ├── settings/              # preferences (theme / fonts / mirrors / timing)
│   ├── shell/                 # bottom-nav / rail / desktop sidebar
│   └── theme/                 # design tokens
├── core/                      # cross-cutting helpers
│   ├── error/                 # failure / display
│   ├── logging/               # global logger + Dio interceptor + ring buffer
│   ├── platform/              # downloads, installer
│   ├── result/                # Result / Failure pattern
│   └── storage/               # JSON cache
├── integrations/              # external integrations
│   ├── app_update/            # GitHub release + mirror downloader
│   ├── calendar/              # ICS exporter
│   ├── campus_notices/        # campus board
│   ├── electricity_recharge/  # electricity / recharge
│   ├── graduate_notices/      # graduate board
│   ├── hitokoto/              # daily quote
│   ├── school_news/           # official news
│   └── school_portal/         # SSO + jxgl + gym + personal info
│       └── sso/               # credential transformer, slider, CAS
├── modules/                   # feature modules (domain/data/presentation each)
│   ├── auth/                  # password + SMS login, slider sheet
│   ├── electricity/           # dorm electricity
│   ├── exams/                 # exams
│   ├── grades/                # grades
│   ├── gym_booking/           # gym
│   ├── home/                  # home
│   ├── notices/               # notices
│   ├── personal_info/         # active sessions / logs
│   ├── profile/               # profile + settings
│   ├── schedule/              # schedule
│   ├── school_news/           # school news
│   └── services/              # campus services portal
└── shared/                    # cross-module widgets
```

## Release Pipeline

`.github/workflows/release.yml` runs whenever `version:` in `pubspec.yaml`
changes:

1. `ubuntu-latest` runs `flutter build apk --release`, producing a universal
   APK with the prepared signing config.
2. A GitHub Release is created with the changelog rendered from the new
   commits since the previous tag.
3. APK and SHA1 checksum files are attached.

Required secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

## Contributing

1. Fork
2. `git checkout -b feature/<topic>`
3. `git commit -m '...'`
4. `git push origin feature/<topic>`
5. Open a Pull Request

## License

MIT License — see [LICENSE](LICENSE).

---

<div align="center">
  <sub>Built with ❤️ for Wuyi University students</sub>
</div>
