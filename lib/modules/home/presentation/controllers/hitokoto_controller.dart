import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/hitokoto_quote.dart';

final hitokotoControllerProvider =
    AsyncNotifierProvider<HitokotoController, HitokotoQuote>(
      HitokotoController.new,
      retry: (_, _) => null,
    );

class HitokotoController extends AsyncNotifier<HitokotoQuote> {
  static const _fallbackQuotes = [
    HitokotoQuote(text: '把今天过成一页好看的手账。', source: 'Uni Yi'),
    HitokotoQuote(text: '先完成一小步，剩下的路会自己亮一点。', source: 'Uni Yi'),
    HitokotoQuote(text: '晚风很轻，ddl 也可以一点点处理。', source: 'Uni Yi'),
    HitokotoQuote(text: '课间的三分钟，也算认真生活。', source: 'Uni Yi'),
  ];

  bool _refreshing = false;

  @override
  Future<HitokotoQuote> build() async {
    return _fetchOrFallback();
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final previous = state.asData?.value;
    try {
      state = AsyncData(await _fetchOrFallback(previous: previous));
    } finally {
      _refreshing = false;
    }
  }

  Future<HitokotoQuote> _fetchOrFallback({HitokotoQuote? previous}) async {
    final result = await ref.read(hitokotoApiProvider).fetchQuote();
    if (result case Success<HitokotoQuote>(data: final quote)) {
      return quote;
    }

    return _nextFallback(previous: previous);
  }

  HitokotoQuote _nextFallback({HitokotoQuote? previous}) {
    final random = Random();
    var quote = _fallbackQuotes[random.nextInt(_fallbackQuotes.length)];
    if (previous != null && _fallbackQuotes.length > 1) {
      var guard = 0;
      while (quote.text == previous.text && guard < 4) {
        quote = _fallbackQuotes[random.nextInt(_fallbackQuotes.length)];
        guard += 1;
      }
    }
    return HitokotoQuote(
      text: quote.text,
      source: quote.source,
      author: quote.author,
      uuid: quote.uuid,
      fallback: true,
    );
  }
}
