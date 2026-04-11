<div align="center">
  <img src="assets/logo/pixel_cat_logo_1024.png" width="120" height="120" alt="拾邑 Logo">

  <h1>拾邑</h1>

  <p><strong>All-in-one campus assistant for Wuyi University</strong></p>

  <p>
    <img src="https://img.shields.io/badge/Flutter-3.29+-02569B?style=flat-square&logo=flutter" alt="Flutter">
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

**拾邑** (Shí Yì) is a campus assistant app designed for students at Wuyi University (五邑大学). It integrates academic information, campus services, and daily utilities into one cohesive experience.

> 拾取校园点滴，邑你相伴同行。
>
> **Current support status**
> This project currently supports both undergraduate and graduate student accounts.
> Academic features adapt to the corresponding school portal routes automatically.

## Features

- **Unified Authentication** — Secure SSO login via the university portal, credentials stored locally with AES encryption
- **Multi-Account Support** — Supports both undergraduate and graduate student accounts
- **Class Schedule** — Weekly and daily views with semester switching
- **Grades** — Semester-by-semester grade queries
- **Exams** — Exam schedule with time and location details
- **Campus Notices** — Categorized university announcements and newsletters
- **Electricity Monitor** — Real-time dormitory electricity balance and recharge history
- **Gym Booking** — Browse venues and book time slots online
- **Campus Services** — One-stop portal for all school web services
- **Personalization** — Theme colors, font presets, compact mode, dark mode, and high contrast support

## Screenshots

| Landing | Home | Schedule | Notice |
| --- | --- | --- | --- |
| ![Landing](docs/screenshots/homepage%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.05.08.png) | ![Home](docs/screenshots/home%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.02.48.png) | ![Schedule](docs/screenshots/course%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.05.36.png) | ![Notice](docs/screenshots/notice%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.05.41.png) |

| Electricity | Services | Exams | Settings |
| --- | --- | --- | --- |
| ![Electricity](docs/screenshots/electric%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.06.17.png) | ![Services](docs/screenshots/service%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.06.23.png) | ![Exams](docs/screenshots/exam%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.07.44.png) | ![Settings](docs/screenshots/setting%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.05.45.png) |

| Gym Booking | Personalized Recommendations | Venue Search |
| --- | --- | --- |
| ![Gym Booking](docs/screenshots/order-%20iPhone%2016%20Plus%20-%202026-04-09%20at%2009.24.56.png) | ![Personalized Recommendations](docs/screenshots/like%20-%20iPhone%2016%20Plus%20-%202026-04-09%20at%2009.25.20.png) | ![Venue Search](docs/screenshots/search%20-%20iPhone%2016%20Plus%20-%202026-04-09%20at%2009.25.26.png) |

## Getting Started

### Prerequisites

- Flutter SDK >= 3.29.0
- Dart SDK >= 3.9.2
- Android Studio or VS Code
- Android SDK (for Android builds)
- Xcode 15+ (for iOS/macOS builds, macOS only)

### Installation

```bash
# Clone the repository
git clone https://github.com/<your-username>/uni_yi.git
cd uni_yi

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Build

```bash
# Android APK
flutter build apk

# Android App Bundle (for Play Store)
flutter build appbundle --release

# iOS
flutter build ios --release

# Web
flutter build web

# Desktop
flutter build macos
flutter build windows
flutter build linux
```

## Tech Stack

| Category | Technology |
| --- | --- |
| Framework | Flutter 3.29+ / Dart 3.9+ |
| State Management | Riverpod |
| Routing | GoRouter |
| Networking | Dio |
| Local Storage | SharedPreferences + FlutterSecureStorage |
| Encryption | encrypt (AES) |
| Architecture | Clean Architecture / Feature-first |

## Project Structure

```
lib/
├── main.dart                  # App entry point
├── app/                       # App-level configuration
│   ├── bootstrap/             # Initialization
│   ├── di/                    # Dependency injection
│   ├── router/                # Routing
│   ├── settings/              # Preferences
│   ├── shell/                 # Navigation shell
│   └── theme/                 # Theming
├── core/                      # Core utilities
│   ├── error/                 # Error handling & display
│   ├── logging/               # Logging
│   ├── models/                # Base models
│   ├── network/               # Network layer
│   ├── result/                # Result pattern
│   └── storage/               # Storage helpers
├── integrations/              # External integrations
│   └── school_portal/         # University portal integration
│       ├── clients/           # API clients
│       ├── dto/               # Data transfer objects
│       ├── mappers/           # Data mapping
│       ├── parsers/           # Response parsing
│       └── sso/               # SSO authentication
├── modules/                   # Feature modules
│   ├── auth/                  # Authentication
│   ├── electricity/           # Electricity monitoring
│   ├── exams/                 # Exam schedule
│   ├── grades/                # Grades
│   ├── gym_booking/           # Gym booking
│   ├── home/                  # Home page
│   ├── notices/               # Campus notices
│   ├── profile/               # Profile & settings
│   └── schedule/              # Class schedule
└── shared/                    # Shared widgets & utilities
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<div align="center">
  <sub>Built with ❤️ for Wuyi University students</sub>
</div>
