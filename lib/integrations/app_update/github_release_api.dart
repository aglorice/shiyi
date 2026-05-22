import 'dart:typed_data';

import 'package:dio/dio.dart';

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
  }) async {
    try {
      final response = await _dio.getUri<List<int>>(
        uri,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: onReceiveProgress,
      );
      if (response.statusCode != 200 || response.data == null) {
        return FailureResult(
          NetworkFailure('安装包下载失败，状态码 ${response.statusCode ?? '-'}。'),
        );
      }
      return Success(Uint8List.fromList(response.data!));
    } on DioException catch (error, stackTrace) {
      _logger.error('下载 GitHub 安装包失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        NetworkFailure('安装包下载失败，请稍后重试。', cause: error, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      _logger.error('处理 GitHub 安装包失败', error: error, stackTrace: stackTrace);
      return FailureResult(
        ParsingFailure('安装包处理失败。', cause: error, stackTrace: stackTrace),
      );
    }
  }
}
