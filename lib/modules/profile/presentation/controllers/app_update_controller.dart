import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../app/app_links.dart';
import '../../../../app/di/app_providers.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/platform/app_installer_service.dart';
import '../../../../core/platform/file_save_service.dart';
import '../../../../core/result/result.dart';
import '../../../../integrations/app_update/github_release_api.dart';

class InstalledAppInfo {
  const InstalledAppInfo({
    required this.appName,
    required this.version,
    required this.buildNumber,
    required this.packageName,
  });

  final String appName;
  final String version;
  final String buildNumber;
  final String packageName;

  String get versionLabel =>
      buildNumber.isEmpty ? version : '$version+$buildNumber';
}

class AppUpdateStatus {
  const AppUpdateStatus({required this.installed, this.release, this.failure});

  final InstalledAppInfo installed;
  final GitHubReleaseInfo? release;
  final Failure? failure;

  bool get hasError => failure != null;
  bool get hasRelease => release != null;
  bool get hasUpdate =>
      release != null &&
      _compareSemanticVersions(release!.version, installed.version) > 0;

  String get currentVersionLabel => installed.versionLabel;
  String? get latestVersionLabel => release?.version;
  GitHubReleaseAsset? get apkAsset => release?.apkAsset;
}

class AppUpdateActionState {
  const AppUpdateActionState({
    this.busy = false,
    this.progress,
    this.downloadedFile,
    this.downloadedVersion,
  });

  final bool busy;
  final double? progress;
  final SavedFile? downloadedFile;
  final String? downloadedVersion;

  AppUpdateActionState copyWith({
    bool? busy,
    double? progress,
    bool clearProgress = false,
    SavedFile? downloadedFile,
    bool clearDownloadedFile = false,
    String? downloadedVersion,
    bool clearDownloadedVersion = false,
  }) {
    return AppUpdateActionState(
      busy: busy ?? this.busy,
      progress: clearProgress ? null : (progress ?? this.progress),
      downloadedFile: clearDownloadedFile
          ? null
          : (downloadedFile ?? this.downloadedFile),
      downloadedVersion: clearDownloadedVersion
          ? null
          : (downloadedVersion ?? this.downloadedVersion),
    );
  }
}

class AppUpdateActionOutcome {
  const AppUpdateActionOutcome({
    required this.file,
    required this.installResult,
  });

  final SavedFile file;
  final ApkInstallResult installResult;
}

final installedAppInfoProvider = FutureProvider<InstalledAppInfo>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return InstalledAppInfo(
    appName: info.appName,
    version: info.version,
    buildNumber: info.buildNumber,
    packageName: info.packageName,
  );
});

final appUpdateStatusProvider = FutureProvider.autoDispose<AppUpdateStatus>((
  ref,
) async {
  final installed = await ref.watch(installedAppInfoProvider.future);
  final latestResult = await ref
      .read(gitHubReleaseApiProvider)
      .fetchLatestRelease(owner: appGitHubOwner, repo: appGitHubRepo);

  return switch (latestResult) {
    Success<GitHubReleaseInfo>(data: final release) => AppUpdateStatus(
      installed: installed,
      release: release,
    ),
    FailureResult<GitHubReleaseInfo>(failure: final failure) => AppUpdateStatus(
      installed: installed,
      failure: failure,
    ),
  };
});

final appUpdateActionStateProvider = StateProvider<AppUpdateActionState>(
  (ref) => const AppUpdateActionState(),
);

final appUpdateControllerProvider = Provider<AppUpdateController>(
  AppUpdateController.new,
);

class AppUpdateController {
  AppUpdateController(this._ref);

  final Ref _ref;

  Future<Result<AppUpdateActionOutcome>> downloadOrInstall(
    AppUpdateStatus status,
  ) async {
    final release = status.release;
    if (release == null) {
      return FailureResult(
        status.failure ?? const BusinessFailure('暂时无法获取版本信息。'),
      );
    }

    final asset = release.apkAsset;
    if (asset == null) {
      return const FailureResult(BusinessFailure('最新版本未提供 APK 安装包。'));
    }

    final currentState = _ref.read(appUpdateActionStateProvider);
    if (currentState.downloadedFile != null &&
        currentState.downloadedVersion == release.version) {
      return _installFile(currentState.downloadedFile!);
    }

    _ref.read(appUpdateActionStateProvider.notifier).state = currentState
        .copyWith(busy: true, progress: 0);

    final preferences = _ref.read(appPreferencesControllerProvider);
    final preferredMirror = preferences.resolvedGithubMirrorBundle.selected;

    final downloadResult = await _ref
        .read(gitHubReleaseApiProvider)
        .downloadAsset(
          Uri.parse(asset.downloadUrl),
          preferredMirror: preferredMirror,
          onReceiveProgress: (received, total) {
            if (total <= 0) {
              _ref.read(appUpdateActionStateProvider.notifier).state = _ref
                  .read(appUpdateActionStateProvider)
                  .copyWith(busy: true, clearProgress: true);
              return;
            }

            _ref.read(appUpdateActionStateProvider.notifier).state = _ref
                .read(appUpdateActionStateProvider)
                .copyWith(busy: true, progress: received / total);
          },
        );

    if (downloadResult case FailureResult<Uint8List>(failure: final failure)) {
      _ref.read(appUpdateActionStateProvider.notifier).state = _ref
          .read(appUpdateActionStateProvider)
          .copyWith(busy: false, clearProgress: true);
      return FailureResult(failure);
    }

    final saveResult = await _ref
        .read(fileSaveServiceProvider)
        .saveBytesSafely(
          fileName: asset.name,
          bytes: downloadResult.requireValue(),
          subdirectory: '',
          failureLabel: '安装包',
        );

    if (saveResult case FailureResult<SavedFile>(failure: final failure)) {
      _ref.read(appUpdateActionStateProvider.notifier).state = _ref
          .read(appUpdateActionStateProvider)
          .copyWith(busy: false, clearProgress: true);
      return FailureResult(failure);
    }

    final savedFile = saveResult.requireValue();
    _ref.read(appUpdateActionStateProvider.notifier).state = _ref
        .read(appUpdateActionStateProvider)
        .copyWith(
          busy: false,
          clearProgress: true,
          downloadedFile: savedFile,
          downloadedVersion: release.version,
        );

    return _installFile(savedFile);
  }

  Future<Result<AppUpdateActionOutcome>> _installFile(SavedFile file) async {
    try {
      final installResult = await _ref
          .read(appInstallerServiceProvider)
          .installApk(fileName: file.fileName, path: file.path, uri: file.uri);
      return Success(
        AppUpdateActionOutcome(file: file, installResult: installResult),
      );
    } on PlatformException catch (error, stackTrace) {
      return FailureResult(
        BusinessFailure(
          error.message?.trim().isNotEmpty == true
              ? '安装启动失败：${error.message}'
              : '安装启动失败，请稍后重试。',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } catch (error, stackTrace) {
      return FailureResult(
        BusinessFailure('安装启动失败，请稍后重试。', cause: error, stackTrace: stackTrace),
      );
    }
  }
}

int _compareSemanticVersions(String left, String right) {
  final leftParts = left.split('.').map(_parseVersionPart).toList();
  final rightParts = right.split('.').map(_parseVersionPart).toList();
  final maxLength = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;

  for (var index = 0; index < maxLength; index += 1) {
    final leftValue = index < leftParts.length ? leftParts[index] : 0;
    final rightValue = index < rightParts.length ? rightParts[index] : 0;
    if (leftValue != rightValue) {
      return leftValue.compareTo(rightValue);
    }
  }

  return 0;
}

int _parseVersionPart(String value) {
  final normalized = value.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(normalized) ?? 0;
}
