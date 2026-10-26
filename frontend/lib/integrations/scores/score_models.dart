/// One search result from /api/scores/search.
class ScoreSummary {
  final String id;
  final String title;
  final String composer;

  /// Read from the score's MusicXML on the server; null or empty when the
  /// file does not say.
  final double? tempoBpm;
  final String timeSignature;

  /// As the catalogue writes it ("1722", "ca. 1785"); empty when unknown.
  final String composedDate;

  /// What authored guidelines are matched against ("baroque", "j-s-bach").
  final List<String> tags;

  const ScoreSummary({
    required this.id,
    required this.title,
    required this.composer,
    this.tempoBpm,
    this.timeSignature = '',
    this.composedDate = '',
    this.tags = const [],
  });

  factory ScoreSummary.fromJson(Map<String, dynamic> json) => ScoreSummary(
    id: json['id'].toString(),
    title: json['title'] as String? ?? 'Untitled',
    composer: json['composer'] as String? ?? '',
    tempoBpm: (json['tempo_bpm'] as num?)?.toDouble(),
    timeSignature: json['time_signature'] as String? ?? '',
    composedDate: json['composed_date'] as String? ?? '',
    tags: [for (final t in json['tags'] as List<dynamic>? ?? const []) '$t'],
  );
}

/// A score ready to display: its summary plus the MusicXML already fetched,
/// so the practice screen never has to make a second request.
class LoadedScore {
  final ScoreSummary summary;
  final String musicXml;

  const LoadedScore({required this.summary, required this.musicXml});
}
