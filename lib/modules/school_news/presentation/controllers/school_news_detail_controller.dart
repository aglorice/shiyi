import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/school_news.dart';

final schoolNewsDetailProvider = FutureProvider.autoDispose
    .family<SchoolNewsDetail, SchoolNewsItem>((ref, item) async {
      final result = await ref.read(fetchSchoolNewsDetailUseCaseProvider)(
        item: item,
        forceRefresh: true,
      );
      return result.requireValue();
    });

final schoolNewsImageBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, ({String url, String referer})>((ref, request) async {
      final result = await ref
          .read(wyuSchoolNewsApiProvider)
          .fetchPublicBytes(
            resourceUri: Uri.parse(request.url),
            referer: Uri.tryParse(request.referer),
          );

      if (result case Success<Uint8List>(data: final bytes)) {
        ref.keepAlive();
        return bytes;
      }

      return result.requireValue();
    });
