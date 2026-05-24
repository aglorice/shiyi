/// 用户在 authserver 上的"应用访问/登录/密码变更"日志条目。
///
/// authserver 一份接口同时承担三种 operType：
/// - 0 → 登录记录（含浏览器、IP、归属地、登录方式、是否成功）
/// - 2 → 密码维护记录（操作类型、IP、是否成功）
/// - 3 → 应用访问记录（appName、appurl、IP）
///
/// 这里把三种类型 normalize 成同一份模型，调用方按 [LogType] 区分展示。
enum UserLogType { authentication, passwordMaintain, appAccess }

class UserLogEntry {
  const UserLogEntry({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.timeLabel,
    required this.success,
    required this.ip,
    this.title,
    this.subtitle,
    this.location,
    this.userAgent,
    this.errorMessage,
    this.logoutTime,
    this.logoutTimeLabel,
    this.appUrl,
  });

  final String id;
  final UserLogType type;
  final DateTime timestamp;
  final String timeLabel;
  final bool success;
  final String ip;

  /// 视图层主标题：app 访问就是 appName，登录就是 loginTypeDesc，密码就是 opertype
  final String? title;

  /// 副标题：根据 type 不同含义不同。
  final String? subtitle;

  /// 「广东省佛山市」之类，登录日志才有。
  final String? location;

  /// 「windows_10 chrome13/131.0.0.0」之类，登录日志才有。
  final String? userAgent;

  /// 失败原因（密码错误等），登录日志才有。
  final String? errorMessage;

  /// 登出时间（毫秒），登录日志才有。
  final DateTime? logoutTime;
  final String? logoutTimeLabel;

  /// 应用访问的 URL。
  final String? appUrl;
}

class UserLogPage {
  const UserLogPage({
    required this.total,
    required this.items,
  });

  final int total;
  final List<UserLogEntry> items;
}

/// 踢出在线会话的结果。
/// - [success]：踢成功，刷新列表即可。
/// - [selfKicked]：踢的就是当前 session，服务端已经让 cookies 失效，
///   调用方应该走登出登录、回登录页的流程。
/// - [error]：网络错误或服务端返回非 0 code。
enum KickOnlineResult { success, selfKicked, error }

/// 「当前在线」条目。结构与 authentication 日志近似但精简了一点。
class OnlineSession {
  const OnlineSession({
    required this.id,
    required this.ip,
    required this.location,
    required this.userAgent,
    required this.loginTime,
    required this.loginTimeLabel,
    required this.loginTypeDesc,
    required this.isCurrent,
  });

  final String id;
  final String ip;
  final String location;
  final String userAgent;
  final DateTime loginTime;
  final String loginTimeLabel;
  final String loginTypeDesc;

  /// 服务端 currentBrowserTGC 命中的那个 session。
  final bool isCurrent;
}
