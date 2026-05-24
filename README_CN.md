<div align="center">
  <img src="assets/logo/pixel_cat_logo_1024.png" width="120" height="120" alt="拾邑 Logo">

  <h1>拾邑</h1>

  <p><strong>五邑大学一站式校园助手</strong></p>

  <p>
    <img src="https://img.shields.io/badge/Flutter-3.35+-02569B?style=flat-square&logo=flutter" alt="Flutter">
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

**拾邑**是一款面向五邑大学学生的校园助手应用，把教务、校园服务和日常工具整合在一起。

> 拾取校园点滴，邑你相伴同行。
>
> **当前支持范围**
> 同时支持本科生与研究生账号，教务能力会按学籍自动切换接口。

## 功能特性

### 登录与账号

- **学号 + 密码登录** — 复刻学校 SSO 全流程，密码 AES 加密在本地保存，支持自动续期
- **手机号 + 短信验证码登录** — 完整逆向了滑块图形验证（自动识别 + 真人轨迹）+ 验证码下发
- **图形/滑块验证码** — 学校触发风控时自动弹出滑块面板，沿用 web 端拼图算法，支持失败重试与人工拖动
- **远端注销** — 退出登录会调用 `/authserver/logout` 让远端 CASTGC 失效，本地与服务端双清

### 教务

- **课程表** — 周/今日视图，多学期切换，自定义节次时间表（上午/下午/晚上 + 节长 + 大课间），自定义背景图，导出 ICS 智能识别单双周与跳周
- **成绩查询** — 逐学期查看成绩
- **考试安排** — 时间地点详情
- **校内通知** — 校内通知公告 + 研究生通知双通道分类浏览
- **学校要闻** — 官网新闻同步抓取，离线缓存

### 校园服务

- **宿舍电量** — 实时余额、用电曲线、充值历史
- **体育馆预约** — 浏览场地、查看可约时段、在线预约、查看个人订单、踢出他处会话
- **校园 Web 服务** — 单点登录直达学校 ehall 任意服务（无须再登）

### 个人中心（authserver）

- **当前在线** — 列出所有在线会话，支持踢出（包括踢自己自动登出回登录页）
- **登录记录 / 应用访问 / 密码维护** — 三种日志分页加载，下拉刷新 + 滚动到底无感加载下一页
- **IP 归属地** — 学校原始数据 + 离线 IP 库回填，长按胶囊可复制 IP

### 工具与体验

- **首页一言** — 可关，宠物表情自动随机
- **请求日志** — 全应用 7 个 Dio 实例统一日志，详情页可看请求体/响应体（敏感字段自动脱敏）
- **GitHub 镜像加速** — 内置 4 个公共镜像，支持自定义新增、并发测速、单选生效，下载失败自动回落原始
- **应用内更新** — 检查 GitHub Releases 最新版，进度条下载 APK，自动调起系统安装器
- **存储与缓存** — 一键清缓存，重置外观偏好
- **多端布局** — 手机端紧凑布局，宽屏自动启用 NavigationRail/侧边栏，Windows / macOS 桌面端开箱可用

### 个性化

- **主题色** — 三套预设
- **深色模式** — 跟随系统 / 手动切换
- **字号** — 默认 90%，可在 80%-120% 调整
- **紧凑模式 / 高对比度**
- **课表背景** — 内置纹理 + 自定义图片

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

- Flutter SDK >= 3.35.0（开发用 3.35.6 验证）
- Dart SDK >= 3.9.2
- Android Studio 或 VS Code
- Android SDK（Android 开发）
- Xcode 16+（iOS/macOS 开发，仅限 macOS）

### 安装

```bash
git clone https://github.com/aglorice/uni_yi.git
cd uni_yi
flutter pub get
flutter run
```

### 构建

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS
flutter build ios --release

# 桌面端
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

### 重新生成系统图标

```bash
dart run flutter_launcher_icons
```

会按 `pubspec.yaml` 里的 `flutter_launcher_icons` 配置重新生成 Android adaptive
图标 + iOS AppIcon 全套。

## 技术栈

| 类别 | 技术 |
| --- | --- |
| 框架 | Flutter 3.35+ / Dart 3.9+ |
| 状态管理 | Riverpod 3.x |
| 路由 | GoRouter 17.x（refreshListenable 触发 redirect 重评） |
| 网络请求 | Dio + 自定义日志拦截器（敏感字段脱敏） |
| 本地存储 | SharedPreferences + FlutterSecureStorage |
| 加密 | encrypt（AES-CBC + PKCS7） |
| WebView | webview_flutter（同步登录态用） |
| 图标 | flutter_launcher_icons（iOS squircle + Android adaptive） |
| 架构 | Clean-ish / Feature-first，每个模块自带 domain / data / presentation |

## 项目结构

```
lib/
├── main.dart                  # 应用入口
├── app/                       # 应用配置
│   ├── bootstrap/             # 启动 / 初始化
│   ├── di/                    # 依赖注入
│   ├── layout/                # 断点 / 自适应布局
│   ├── router/                # 路由（GoRouter）
│   ├── settings/              # 偏好（主题、字体、镜像、节次时间表…）
│   ├── shell/                 # 主框架（底栏 / NavigationRail / 桌面侧栏）
│   └── theme/                 # 主题与设计令牌
├── core/                      # 核心工具
│   ├── error/                 # 错误处理与展示
│   ├── logging/               # 全局日志 + 接口日志环形缓冲
│   ├── platform/              # 平台桥接（系统下载、安装器…）
│   ├── result/                # Result / Failure 模式
│   └── storage/               # JSON 缓存
├── integrations/              # 外部集成
│   ├── app_update/            # GitHub Release 检查 + 镜像下载
│   ├── calendar/              # ICS 导出
│   ├── campus_notices/        # 校内通知
│   ├── electricity_recharge/  # 电费 / 充值
│   ├── graduate_notices/      # 研究生通知
│   ├── hitokoto/              # 一言
│   ├── school_news/           # 学校要闻
│   └── school_portal/         # SSO + 教务系统 + 体育馆 + 个人中心
│       └── sso/               # 凭证加密、滑块、CAS 流程
├── modules/                   # 功能模块（每个内部分 domain/data/presentation）
│   ├── auth/                  # 学号密码 + 短信登录 + 滑块
│   ├── electricity/           # 电量
│   ├── exams/                 # 考试
│   ├── grades/                # 成绩
│   ├── gym_booking/           # 体育馆
│   ├── home/                  # 首页
│   ├── notices/               # 通知
│   ├── personal_info/         # 个人中心 / 在线 / 日志
│   ├── profile/               # 个人页与设置
│   ├── schedule/              # 课表
│   ├── school_news/           # 学校要闻
│   └── services/              # 校园服务
└── shared/                    # 跨模块组件
```

## 发版

`.github/workflows/release.yml` 会在 `pubspec.yaml` 里 `version` 变化时自动：

1. 在 `ubuntu-latest` 跑 `flutter build apk --release` 输出 universal APK；
2. 创建 GitHub Release，Body 渲染 commit list 中文格式；
3. 把 APK 与 SHA1 校验文件作为 Release 附件上传。

签名所需 secret：`ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` /
`ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`。

## 参与贡献

欢迎贡献代码！

1. Fork 本仓库
2. 新建分支 `git checkout -b feature/<topic>`
3. 提交 `git commit -m '...'`
4. 推送 `git push origin feature/<topic>`
5. 发起 Pull Request

## 开源许可

MIT License — 详见 [LICENSE](LICENSE)。

---

<div align="center">
  <sub>Built with ❤️ for Wuyi University students</sub>
</div>
