class PortalCookie {
  const PortalCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.secure = false,
    this.httpOnly = false,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final bool httpOnly;

  bool matches(Uri uri) {
    final normalizedDomain = domain.startsWith('.')
        ? domain.substring(1)
        : domain;
    final hostMatches =
        uri.host == normalizedDomain || uri.host.endsWith('.$normalizedDomain');
    if (!hostMatches) {
      return false;
    }

    if (!uri.path.startsWith(path)) {
      return false;
    }

    if (secure && uri.scheme != 'https') {
      return false;
    }

    return true;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
    'secure': secure,
    'httpOnly': httpOnly,
  };

  factory PortalCookie.fromJson(Map<String, dynamic> json) {
    return PortalCookie(
      name: json['name'] as String,
      value: json['value'] as String,
      domain: json['domain'] as String,
      path: json['path'] as String? ?? '/',
      secure: json['secure'] as bool? ?? false,
      httpOnly: json['httpOnly'] as bool? ?? false,
    );
  }
}

class PortalUserProfile {
  const PortalUserProfile({
    required this.userName,
    required this.userAccount,
    this.deptName,
  });

  final String userName;
  final String userAccount;
  final String? deptName;

  Map<String, dynamic> toJson() => {
    'userName': userName,
    'userAccount': userAccount,
    'deptName': deptName,
  };

  factory PortalUserProfile.fromJson(Map<String, dynamic> json) {
    return PortalUserProfile(
      userName: json['userName'] as String? ?? '',
      userAccount: json['userAccount'] as String? ?? '',
      deptName: json['deptName'] as String?,
    );
  }
}

class PortalServiceLink {
  const PortalServiceLink({
    required this.id,
    required this.title,
    required this.url,
    this.description,
    this.iconUrl,
    this.wid,
  });

  final String id;
  final String title;
  final String url;
  final String? description;
  final String? iconUrl;
  final String? wid;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'description': description,
    'iconUrl': iconUrl,
    'wid': wid,
  };

  factory PortalServiceLink.fromJson(Map<String, dynamic> json) {
    return PortalServiceLink(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      description: json['description'] as String?,
      iconUrl: json['iconUrl'] as String?,
      wid: json['wid'] as String?,
    );
  }
}

class AppSession {
  const AppSession({
    required this.userId,
    required this.displayName,
    required this.cookies,
    required this.issuedAt,
    required this.expiresAt,
    this.profile,
    this.serviceLinks = const [],
    this.yjsSessionId,
  });

  final String userId;
  final String displayName;
  final List<PortalCookie> cookies;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final PortalUserProfile? profile;
  final List<PortalServiceLink> serviceLinks;
  final String? yjsSessionId;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool get isUndergraduate => profile?.deptName?.startsWith('本科生') ?? false;
  bool get isGraduate => profile?.deptName?.startsWith('研究生') ?? false;

  String get cookieHeader =>
      cookieHeaderForUri(Uri.parse('https://ehall.wyu.edu.cn/'));

  String cookieHeaderForUri(Uri uri) {
    return cookies
        .where((cookie) => cookie.matches(uri))
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
  }

  AppSession copyWith({
    String? userId,
    String? displayName,
    List<PortalCookie>? cookies,
    DateTime? issuedAt,
    DateTime? expiresAt,
    PortalUserProfile? profile,
    List<PortalServiceLink>? serviceLinks,
    String? yjsSessionId,
    bool clearYjsSessionId = false,
  }) {
    return AppSession(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      cookies: cookies ?? this.cookies,
      issuedAt: issuedAt ?? this.issuedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      profile: profile ?? this.profile,
      serviceLinks: serviceLinks ?? this.serviceLinks,
      yjsSessionId: clearYjsSessionId
          ? null
          : yjsSessionId ?? this.yjsSessionId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'displayName': displayName,
      'cookies': cookies.map((cookie) => cookie.toJson()).toList(),
      'issuedAt': issuedAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'profile': profile?.toJson(),
      'serviceLinks': serviceLinks.map((link) => link.toJson()).toList(),
      'yjsSessionId': yjsSessionId,
    };
  }

  factory AppSession.fromJson(Map<String, dynamic> json) {
    return AppSession(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
      cookies: (json['cookies'] as List<dynamic>? ?? const [])
          .map((item) => PortalCookie.fromJson(item as Map<String, dynamic>))
          .toList(),
      issuedAt: DateTime.parse(json['issuedAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      profile: switch (json['profile']) {
        final Map<String, dynamic> value => PortalUserProfile.fromJson(value),
        _ => null,
      },
      serviceLinks: (json['serviceLinks'] as List<dynamic>? ?? const [])
          .map(
            (item) => PortalServiceLink.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      yjsSessionId: json['yjsSessionId'] as String?,
    );
  }
}
