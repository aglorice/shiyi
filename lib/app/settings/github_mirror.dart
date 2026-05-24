import 'dart:convert';

/// 一个 GitHub 文件加速镜像。
///
/// 形式：用户最终的下载 URL = `${prefix}${github 原始 URL}`。
/// 内置镜像不允许删除，但可以反选不用。
class GithubMirror {
  const GithubMirror({
    required this.id,
    required this.label,
    required this.prefix,
    this.builtin = false,
  });

  final String id;
  final String label;
  final String prefix;
  final bool builtin;

  Uri wrap(Uri original) {
    final raw = original.toString();
    if (!raw.startsWith('https://github.com/')) {
      return original;
    }
    return Uri.parse('$prefix$raw');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'prefix': prefix,
        'builtin': builtin,
      };

  factory GithubMirror.fromJson(Map<String, dynamic> json) => GithubMirror(
        id: json['id'] as String,
        label: json['label'] as String,
        prefix: json['prefix'] as String,
        builtin: json['builtin'] as bool? ?? false,
      );

  static const builtins = <GithubMirror>[
    GithubMirror(
      id: 'gh-proxy.com',
      label: 'gh-proxy.com',
      prefix: 'https://gh-proxy.com/',
      builtin: true,
    ),
    GithubMirror(
      id: 'ghproxy.net',
      label: 'ghproxy.net',
      prefix: 'https://ghproxy.net/',
      builtin: true,
    ),
    GithubMirror(
      id: 'gh.idayer.com',
      label: 'gh.idayer.com',
      prefix: 'https://gh.idayer.com/',
      builtin: true,
    ),
    GithubMirror(
      id: 'ghfast.top',
      label: 'ghfast.top',
      prefix: 'https://ghfast.top/',
      builtin: true,
    ),
  ];

  /// 始终存在的"不走任何镜像"占位项。
  static const direct = GithubMirror(
    id: '__direct__',
    label: '直连 GitHub',
    prefix: '',
    builtin: true,
  );
}

class GithubMirrorBundle {
  const GithubMirrorBundle({
    required this.mirrors,
    required this.selectedId,
  });

  /// 用户可见的镜像列表（含 [GithubMirror.direct] 在第一位）。
  final List<GithubMirror> mirrors;

  /// 当前选中的镜像 id；默认是第一个内置镜像。
  final String selectedId;

  GithubMirror get selected =>
      mirrors.firstWhere((m) => m.id == selectedId, orElse: () => mirrors.first);

  GithubMirrorBundle copyWith({
    List<GithubMirror>? mirrors,
    String? selectedId,
  }) =>
      GithubMirrorBundle(
        mirrors: mirrors ?? this.mirrors,
        selectedId: selectedId ?? this.selectedId,
      );

  /// 加载默认配置：直连 + 全部内置镜像，默认选第一个内置（gh-proxy）。
  static GithubMirrorBundle initial() => GithubMirrorBundle(
        mirrors: [GithubMirror.direct, ...GithubMirror.builtins],
        selectedId: GithubMirror.builtins.first.id,
      );

  Map<String, dynamic> toJson() => {
        'selectedId': selectedId,
        'custom': mirrors.where((m) => !m.builtin).map((m) => m.toJson()).toList(),
      };

  static GithubMirrorBundle fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return initial();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final custom = (json['custom'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(GithubMirror.fromJson)
          .toList();
      final selectedId =
          json['selectedId'] as String? ?? GithubMirror.builtins.first.id;
      return GithubMirrorBundle(
        mirrors: [GithubMirror.direct, ...GithubMirror.builtins, ...custom],
        selectedId: selectedId,
      );
    } catch (_) {
      return initial();
    }
  }

  String toJsonString() => jsonEncode(toJson());
}
