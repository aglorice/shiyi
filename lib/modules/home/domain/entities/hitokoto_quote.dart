class HitokotoQuote {
  const HitokotoQuote({
    required this.text,
    this.source,
    this.author,
    this.uuid,
    this.fallback = false,
  });

  final String text;
  final String? source;
  final String? author;
  final String? uuid;
  final bool fallback;

  String get sourceLabel {
    final parts = [
      if (author != null && author!.trim().isNotEmpty) author!.trim(),
      if (source != null && source!.trim().isNotEmpty) '《${source!.trim()}》',
    ];
    return parts.isEmpty ? '一言' : parts.join(' · ');
  }
}
