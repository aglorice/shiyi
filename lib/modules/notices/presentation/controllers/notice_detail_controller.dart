import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/platform/file_save_service.dart';
import '../../../../core/result/result.dart';
import '../../../auth/domain/entities/app_session.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../domain/entities/campus_notice.dart';

final noticeDetailProvider = FutureProvider.autoDispose
    .family<CampusNoticeDetail, CampusNoticeItem>((ref, item) async {
      return switch (item.category.board) {
        NoticeBoardSource.campus => _loadCampusNoticeDetail(ref, item),
        NoticeBoardSource.graduate => _loadGraduateNoticeDetail(ref, item),
      };
    });

final noticeImageBytesProvider = FutureProvider.autoDispose
    .family<
      Uint8List,
      ({NoticeBoardSource source, String url, String referer})
    >((ref, request) async {
      final result = await switch (request.source) {
        NoticeBoardSource.campus => _loadCampusNoticeImageBytes(
          ref,
          imageUrl: request.url,
          referer: request.referer,
        ),
        NoticeBoardSource.graduate =>
          ref
              .read(wyuGraduateNoticeApiProvider)
              .fetchPublicBytes(
                resourceUri: Uri.parse(request.url),
                referer: Uri.tryParse(request.referer),
              ),
      };

      if (result case Success<Uint8List>(data: final bytes)) {
        ref.keepAlive();
        return bytes;
      }

      return result.requireValue();
    });

final noticeAttachmentDownloadingProvider = StateProvider.autoDispose
    .family<bool, String>((ref, url) => false);

final noticeImageSavingProvider = StateProvider.autoDispose
    .family<bool, String>((ref, url) => false);

final noticeAttachmentDownloaderProvider = Provider<NoticeAttachmentDownloader>(
  NoticeAttachmentDownloader.new,
);

class NoticeAttachmentDownloader {
  NoticeAttachmentDownloader(this._ref);

  final Ref _ref;

  Future<Result<SavedFile>> download({
    required NoticeBoardSource source,
    required CampusNoticeAttachment attachment,
    required Uri referer,
    bool pickLocation = false,
  }) async {
    try {
      final bytesResult = await switch (source) {
        NoticeBoardSource.campus => _fetchCampusAttachmentBytes(
          _ref,
          attachment: attachment,
          referer: referer,
        ),
        NoticeBoardSource.graduate =>
          _ref
              .read(wyuGraduateNoticeApiProvider)
              .fetchPublicBytes(
                resourceUri: Uri.parse(attachment.url),
                referer: referer,
              ),
      };

      if (bytesResult case FailureResult<Uint8List>(failure: final failure)) {
        return FailureResult(failure);
      }

      final bytes = bytesResult.requireValue();
      final fileName = _buildFileName(attachment);
      final fileSaver = _ref.read(fileSaveServiceProvider);
      final saved = pickLocation
          ? await fileSaver.saveBytesWithPicker(
              fileName: fileName,
              bytes: bytes,
            )
          : await fileSaver.saveBytes(
              fileName: fileName,
              bytes: bytes,
              subdirectory: '',
            );
      return Success(saved.copyWith(byteLength: bytes.length));
    } on FileSystemException catch (error, stackTrace) {
      return FailureResult(
        StorageFailure('附件保存失败，请稍后重试。', cause: error, stackTrace: stackTrace),
      );
    } on PlatformException catch (error, stackTrace) {
      if (error.code == 'cancelled') {
        return FailureResult(
          BusinessFailure('附件保存已取消。', cause: error, stackTrace: stackTrace),
        );
      }
      return FailureResult(
        StorageFailure(
          _formatNoticeAttachmentSaveError(error),
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } catch (error, stackTrace) {
      return FailureResult(
        StorageFailure('附件保存失败，请稍后重试。', cause: error, stackTrace: stackTrace),
      );
    }
  }

  String _buildFileName(CampusNoticeAttachment attachment) {
    final raw = attachment.title.trim().isEmpty
        ? '附件'
        : attachment.title.trim();
    final sanitized = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return sanitized.isEmpty ? '附件' : sanitized;
  }
}

Future<CampusNoticeDetail> _loadCampusNoticeDetail(
  Ref ref,
  CampusNoticeItem item,
) async {
  final authState = await ref.watch(authControllerProvider.future);
  final session = authState.session;
  if (session == null) {
    throw const AuthenticationFailure('当前未登录，无法加载通知正文。');
  }

  final result = await ref.read(fetchNoticeDetailUseCaseProvider)(
    session: session,
    item: item,
    forceRefresh: true,
  );

  if (result case Success<CampusNoticeDetail>(data: final detail)) {
    return detail;
  }

  if (result.failureOrNull is SessionExpiredFailure) {
    final refreshed = await ref.read(authRepositoryProvider).refreshSession();
    if (refreshed case Success<AppSession>(data: final newSession)) {
      ref.read(authControllerProvider.notifier).replaceSession(newSession);

      final retry = await ref.read(fetchNoticeDetailUseCaseProvider)(
        session: newSession,
        item: item,
        forceRefresh: true,
      );
      return retry.requireValue();
    }

    ref
        .read(authControllerProvider.notifier)
        .requireReauth(refreshed.failureOrNull!);
  }

  return result.requireValue();
}

Future<CampusNoticeDetail> _loadGraduateNoticeDetail(
  Ref ref,
  CampusNoticeItem item,
) async {
  final result = await ref.read(fetchGraduateNoticeDetailUseCaseProvider)(
    item: item,
    forceRefresh: true,
  );
  return result.requireValue();
}

Future<Result<Uint8List>> _loadCampusNoticeImageBytes(
  Ref ref, {
  required String imageUrl,
  required String referer,
}) async {
  final authState = await ref.watch(authControllerProvider.future);
  final session = authState.session;
  if (session == null) {
    return const FailureResult(AuthenticationFailure('当前未登录，无法加载通知图片。'));
  }

  var result = await ref
      .read(wyuNoticeApiProvider)
      .fetchImageBytes(
        session: session,
        imageUri: Uri.parse(imageUrl),
        referer: Uri.tryParse(referer),
      );

  if (result.failureOrNull is SessionExpiredFailure) {
    final refreshed = await ref.read(authRepositoryProvider).refreshSession();
    if (refreshed case Success<AppSession>(data: final newSession)) {
      ref.read(authControllerProvider.notifier).replaceSession(newSession);

      result = await ref
          .read(wyuNoticeApiProvider)
          .fetchImageBytes(
            session: newSession,
            imageUri: Uri.parse(imageUrl),
            referer: Uri.tryParse(referer),
          );
    } else if (refreshed.failureOrNull != null) {
      ref
          .read(authControllerProvider.notifier)
          .requireReauth(refreshed.failureOrNull!);
      return FailureResult(refreshed.failureOrNull!);
    }
  }

  return result;
}

Future<Result<Uint8List>> _fetchCampusAttachmentBytes(
  Ref ref, {
  required CampusNoticeAttachment attachment,
  required Uri referer,
}) async {
  final authState = await ref.read(authControllerProvider.future);
  final session = authState.session;
  if (session == null) {
    return const FailureResult(AuthenticationFailure('当前未登录，无法下载通知附件。'));
  }

  var result = await ref
      .read(wyuNoticeApiProvider)
      .fetchAttachmentBytes(
        session: session,
        attachmentUri: Uri.parse(attachment.url),
        referer: referer,
      );

  if (result.failureOrNull is SessionExpiredFailure) {
    final refreshed = await ref.read(authRepositoryProvider).refreshSession();
    if (refreshed case Success<AppSession>(data: final newSession)) {
      ref.read(authControllerProvider.notifier).replaceSession(newSession);

      result = await ref
          .read(wyuNoticeApiProvider)
          .fetchAttachmentBytes(
            session: newSession,
            attachmentUri: Uri.parse(attachment.url),
            referer: referer,
          );
    } else if (refreshed.failureOrNull != null) {
      ref
          .read(authControllerProvider.notifier)
          .requireReauth(refreshed.failureOrNull!);
      return FailureResult(refreshed.failureOrNull!);
    }
  }

  return result;
}

String _formatNoticeAttachmentSaveError(PlatformException error) {
  final message = error.message?.trim();
  if (message != null && message.isNotEmpty) {
    return '附件保存失败：$message';
  }
  return '附件保存失败，请稍后重试。';
}
