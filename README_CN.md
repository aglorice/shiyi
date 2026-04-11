<div align="center">
  <img src="assets/logo/pixel_cat_logo_1024.png" width="120" height="120" alt="拾邑 Logo">

  <h1>拾邑</h1>

  <p><strong>五邑大学一站式校园助手</strong></p>

  <p>
    <img src="https://img.shields.io/badge/Flutter-3.29+-02569B?style=flat-square&logo=flutter" alt="Flutter">
    <img src="https://img.shields.io/badge/Dart-3.9+-0175C2?style=flat-square&logo=dart" alt="Dart">
    <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-4CAF50?style=flat-square" alt="Platform">
    <img src="https://img.shields.io/badge/License-MIT-yellow?style=flat-square" alt="License">
  </p>

  <p>
    <a href="#功能特性">功能特性</a> •
    <a href="#截图">截图</a> •
    <a href="#快速开始">快速开始</a> •
    <a href="#技术栈">技术栈</a> •
    <a href="#项目结构">项目结构</a>
  </p>

  <p>
    <a href="README.md">English</a>
  </p>
</div>

---

**拾邑**是一款面向五邑大学学生的校园助手应用，将教务信息、校园服务和日常工具整合为一体。

> 拾取校园点滴，邑你相伴同行。
>
> **当前支持范围**
> 当前已支持本科生和研究生账号。
> 教务能力会根据对应学籍自动适配不同系统入口。

## 功能特性

- **统一身份认证** — 通过学校门户 SSO 安全登录，凭证本地 AES 加密存储
- **多学籍支持** — 同时支持本科生与研究生账号
- **课程表** — 按周/今日查看课程安排，支持多学期切换
- **成绩查询** — 逐学期查看成绩信息
- **考试安排** — 查看考试时间、地点等详细信息
- **校内通知** — 分类浏览校内通知公告和简讯
- **宿舍电量** — 实时监控剩余电量与充值历史
- **体育馆预约** — 浏览场地并在线预约时段
- **校园服务** — 一站式访问校内各类 Web 服务
- **个性化设置** — 主题配色、字体预设、紧凑模式、深色模式、高对比度等

## 截图

| 启动页 | 首页 | 课程表 | 通知 |
| --- | --- | --- | --- |
| ![启动页](docs/screenshots/homepage%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.05.08.png) | ![首页](docs/screenshots/home%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.02.48.png) | ![课程表](docs/screenshots/course%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.05.36.png) | ![通知](docs/screenshots/notice%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.05.41.png) |

| 电费 | 服务 | 考试 | 设置 |
| --- | --- | --- | --- |
| ![电费](docs/screenshots/electric%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.06.17.png) | ![服务](docs/screenshots/service%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.06.23.png) | ![考试](docs/screenshots/exam%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.07.44.png) | ![设置](docs/screenshots/setting%20-%20iPhone%2016%20Plus%20-%202026-04-08%20at%2011.05.45.png) |

| 体育馆预约 | 个性化推荐 | 场地搜索 |
| --- | --- | --- |
| ![体育馆预约](docs/screenshots/order-%20iPhone%2016%20Plus%20-%202026-04-09%20at%2009.24.56.png) | ![个性化推荐](docs/screenshots/like%20-%20iPhone%2016%20Plus%20-%202026-04-09%20at%2009.25.20.png) | ![场地搜索](docs/screenshots/search%20-%20iPhone%2016%20Plus%20-%202026-04-09%20at%2009.25.26.png) |

## 快速开始

### 环境要求

- Flutter SDK >= 3.29.0
- Dart SDK >= 3.9.2
- Android Studio 或 VS Code
- Android SDK（Android 开发）
- Xcode 15+（iOS/macOS 开发，仅限 macOS）

### 安装

```bash
# 克隆仓库
git clone https://github.com/<your-username>/uni_yi.git
cd uni_yi

# 安装依赖
flutter pub get

# 运行
flutter run
```

### 构建

```bash
# Android APK
flutter build apk

# Android App Bundle（上架 Play Store）
flutter build appbundle --release

# iOS
flutter build ios --release

# Web
flutter build web

# 桌面端
flutter build macos
flutter build windows
flutter build linux
```

## 技术栈

| 类别 | 技术 |
| --- | --- |
| 框架 | Flutter 3.29+ / Dart 3.9+ |
| 状态管理 | Riverpod |
| 路由 | GoRouter |
| 网络请求 | Dio |
| 本地存储 | SharedPreferences + FlutterSecureStorage |
| 加密 | encrypt (AES) |
| 架构 | Clean Architecture / Feature-first |

## 项目结构

```
lib/
├── main.dart                  # 应用入口
├── app/                       # 应用配置
│   ├── bootstrap/             # 初始化
│   ├── di/                    # 依赖注入
│   ├── router/                # 路由
│   ├── settings/              # 偏好设置
│   ├── shell/                 # 导航外壳
│   └── theme/                 # 主题
├── core/                      # 核心工具
│   ├── error/                 # 错误处理与展示
│   ├── logging/               # 日志
│   ├── models/                # 基础模型
│   ├── network/               # 网络层
│   ├── result/                # Result 模式
│   └── storage/               # 存储工具
├── integrations/              # 外部集成
│   └── school_portal/         # 学校教务系统集成
│       ├── clients/           # API 客户端
│       ├── dto/               # 数据传输对象
│       ├── mappers/           # 数据映射
│       ├── parsers/           # 响应解析
│       └── sso/               # SSO 认证
├── modules/                   # 功能模块
│   ├── auth/                  # 认证
│   ├── electricity/           # 电量监控
│   ├── exams/                 # 考试安排
│   ├── grades/                # 成绩查询
│   ├── gym_booking/           # 体育馆预约
│   ├── home/                  # 首页
│   ├── notices/               # 校内通知
│   ├── profile/               # 个人中心
│   └── schedule/              # 课程表
└── shared/                    # 共享组件与工具
```

## 参与贡献

欢迎贡献代码！请随时提交 Pull Request。

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 发起 Pull Request

## 开源许可

本项目基于 MIT 协议开源 — 详见 [LICENSE](LICENSE) 文件。

---

<div align="center">
  <sub>Built with ❤️ for Wuyi University students</sub>
</div>
