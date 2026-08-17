/// Free pre-match team availability note published by the HKJC football site.
///
/// The HKJC prints a third-party preview for many of the fixtures it sells,
/// and that preview carries a labelled availability block per team
/// (`停賽`, `上陣成疑`, `受傷／缺陣`). The club names are the Chinese names the
/// HKJC itself quotes, so they join directly onto the fixture feed.
///
/// The HKJC states in the same article that the content comes from a third
/// party and is not verified by the club, which is why [verified] is always
/// `false` here and why the model is only ever allowed to widen a distribution
/// with it, never to move a mean.
class TeamNewsSnapshot {
  const TeamNewsSnapshot({
    required this.teamName,
    required this.capturedAt,
    required this.source,
    required this.suspended,
    required this.doubtful,
    required this.absent,
  });

  factory TeamNewsSnapshot.fromJson(Map<String, Object?> json) {
    List<String> names(String key) =>
        (json[key] as List?)?.whereType<String>().toList() ?? const [];
    return TeamNewsSnapshot(
      teamName: json['teamName'] as String,
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      source: json['source'] as String,
      suspended: names('suspended'),
      doubtful: names('doubtful'),
      absent: names('absent'),
    );
  }

  /// Chinese club name exactly as the HKJC prints it.
  final String teamName;
  final DateTime capturedAt;
  final String source;

  /// Players named as serving a suspension.
  final List<String> suspended;

  /// Players named as unlikely but not ruled out.
  final List<String> doubtful;

  /// Players named as injured or otherwise unavailable.
  final List<String> absent;

  /// Never `true`: the HKJC prints this content with a no-verification notice.
  bool get verified => false;

  /// Doubtful players count half because they may still start.
  double get shortfall =>
      suspended.length + absent.length + 0.5 * doubtful.length;

  bool get isEmpty => suspended.isEmpty && doubtful.isEmpty && absent.isEmpty;

  Map<String, Object?> toJson() => {
    'teamName': teamName,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'source': source,
    'suspended': suspended,
    'doubtful': doubtful,
    'absent': absent,
  };
}
