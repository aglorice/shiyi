import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../app/settings/github_mirror.dart';
import '../../core/error/failure.dart';
import '../../core/logging/api_log_interceptor.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';

class GitHubReleaseAsset {
  const GitHubReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.contentType,
  });

  final String name;
  final String downloadUrl;
  final int size;
  final String? contentType;

  bool get isApk => name.toLowerCase().endsWith('.apk');
}

class GitHubReleaseInfo {
  const GitHubReleaseInfo({
    required this.tagName,
    required this.version,
    required this.title,
    required this.htmlUrl,
    required this.notes,
    required this.publishedAt,
    required this.assets,
  });

  final String tagName;
  final String version;
  final String title;
  final String htmlUrl;
  final String notes;
  final DateTime? publishedAt;
  final List<GitHubReleaseAsset> assets;

  GitHubReleaseAsset? get apkAsset {
    for (final asset in assets) {
      if (asset.isApk) {
        return asset;
      }
    }
    return null;
  }
}

class GitHubReleaseApi {
  GitHubReleaseApi({required AppLogger logger, Dio? dio})
    : _logger = logger,
      _dio =
          dio ??
          (Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 60),
              followRedirects: true,
              validateStatus: (status) => status != null && status < 500,
              headers: const {
                'Accept': 'application/vnd.github+json',
                'User-Agent': 'uni_yi',
              },
            ),
          )..interceptors.add(ApiLogInterceptor(label: 'GitHub')));

  final AppLogger _logger;
  final Dio _dio;

  Future<Result<GitHubReleaseInfo>> fetchLatestRelease({
    required String owner,
    required String repo,
  }) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/releases/latest',
    );

    try {
      final response = await _dio.getUri<Map<String, dynamic>>(uri);
      if (response.statusCode != 200 || response.data == null) {
        return FailureResult(
          NetworkFailure('获取最新版本失败，状态码 ${response.statusCode ?? '-'}。'),
        );
      }

      final data = response.data!;
      final assets = (data['assets'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (item) => GitHubReleaseAsset(
              name: item['name'] as String? ?? '',
              downloadUrl: item['browser_download_url'] as String? ?? '',
              size: item['size'] as int? ?? 0,
              contentType: item['content_type'] as String?,
            ),
          )
          .where((item) => item.name.isNotEmpty && item.downloadUrl.isNotEmpty)
          .toList();

      final tagName = (data['tag_name'] as String? ?? '').trim();
      final version = tagName.replaceFirst(RegExp(r'^v'), '').trim();
      if (version.isEmpty) {
        return const FailureResult(ParsingFailure('最新版本号为空。'));
      }

      return Success(
        GitHubReleaseInfo(
          tagName: tagName,
          version: version,
          title: (data['name'] as String? ?? tagName).trim(),
          htmlUrl: (data['html_url'] as String? ?? '').trim(),
          notes: (data['body'] as String? ?? '').trim(),
          publishedAt: DateTime.tryParse(data['published_at'] as String? ?? ''),
          assets: assets,
        ),
      );
    } on DioException catch (error, stackTrace) {
      _logger.error('获取 GitHub 最新版本失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure('获取最新版本失败，请稍后重试。', cause: error, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      _logger.error('解析 GitHub 最新版本失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        ParsingFailure('解析最新版本失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  Future<Result<Uint8List>> downloadAsset(
    Uri uri, {
    void Function(int received, int total)? onReceiveProgress,
    GithubMirror? preferredMirror,
  }) async {
    // 国内访问 github.com release 包经常不稳定，按顺序尝试镜像站。
    // 任何一站返回 200 即用；都失败再回落到 github 原始 URL。
    final candidates = _buildDownloadCandidates(uri, preferredMirror);
    DioException? lastError;
    for (final candidate in candidates) {
      try {
        _logger.info('[UPDATE] 尝试下载 $candidate');
        final response = await _dio.getUri<List<int>>(
          candidate,
          options: Options(
            responseType: ResponseType.bytes,
            // 镜像可能慢，单站 60s 超时；总尝试上限就靠候选数。
            receiveTimeout: const Duration(seconds: 90),
          ),
          onReceiveProgress: onReceiveProgress,
        );
        if (response.statusCode == 200 && response.data != null) {
          return Success(Uint8List.fromList(response.data!));
        }
        _logger.warn(
          '[UPDATE] 镜像 $candidate 返回 ${response.statusCode}，换下一个',
        );
      } on DioException catch (error) {
        lastError = error;
        _logger.warn('[UPDATE] 镜像 $candidate 失败：${error.message}');
        continue;
      }
    }

    final lastUri = candidates.last;
    _logger.error(
      '所有 GitHub 镜像均下载失败 lastUri=$lastUri',
      error: lastError,
    );
    return FailureResult(
      NetworkFailure(
        '安装包下载失败，请稍后重试。',
        cause: lastError,
        stackTrace: lastError?.stackTrace,
      ),
    );
  }

  /// 构建一个候选下载 URL 列表：preferredMirror（如果给了且不是 direct）
  /// 优先；不行再回落到原始。
  List<Uri> _buildDownloadCandidates(Uri original, GithubMirror? preferred) {
    final raw = original.toString();
    if (!raw.startsWith('https://github.com/')) {
      return [original];
    }
    final list = <Uri>[];
    if (preferred != null && preferred.id != GithubMirror.direct.id) {
      list.add(preferred.wrap(original));
    }
    list.add(original);
    return list;
  }

  /// 测试某个镜像是否可用：发 HEAD 到一个固定的 GitHub 文件。
  /// 返回 ms 延迟；null 表示失败。调用方只用它做 UI 显示，
  /// 不会作为下载策略的硬条件。
  Future<int?> probeMirror(GithubMirror mirror) async {
    // 用 GitHub 自家的 release latest 重定向接口当探针，体积小、永久存在。
    // 直连项也可以测，给用户一个对比基线。
    const probePath = 'https://github.com/octocat/Hello-World/archive/refs/heads/master.zip';
    final probeUri = mirror.id == GithubMirror.direct.id
        ? Uri.parse(probePath)
        : mirror.wrap(Uri.parse(probePath));
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _dio.headUri(
        probeUri,
        options: Options(
          followRedirects: false,
          validateStatus: (s) => s != null,
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      stopwatch.stop();
      // 200/302 都视为正常响应。
      final status = response.statusCode ?? 0;
      if (status >= 200 && status < 400) {
        return stopwatch.elapsedMilliseconds;
      }
      return null;
    } catch (_) {
      stopwatch.stop();
      return null;
    }
  }
}
