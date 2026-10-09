/// How long ago something happened, in words: `vừa xong`, `5 phút trước`, `3 ngày trước`, `2 tuần trước`...
/// [now] is the clock, so a test can fix it.
String relativeTime(DateTime then, {DateTime? now}) {
  final age = (now ?? DateTime.now()).toUtc().difference(then.toUtc());
  // A time in the future (the clock of the server is a little ahead) is "just now", not "-3 minutes ago".
  if (age < const Duration(seconds: 45)) return 'vừa xong';
  if (age < const Duration(hours: 1)) return '${age.inMinutes < 1 ? 1 : age.inMinutes} phút trước';
  if (age < const Duration(days: 1)) return '${age.inHours} giờ trước';
  if (age < const Duration(days: 7)) return '${age.inDays} ngày trước';
  if (age < const Duration(days: 30)) return '${age.inDays ~/ 7} tuần trước';
  if (age < const Duration(days: 365)) return '${age.inDays ~/ 30} tháng trước';
  return '${age.inDays ~/ 365} năm trước';
}

/// A position in a track as `m:ss` (`1:23`), or `h:mm:ss` from one hour on.
String formatPosition(int milliseconds) {
  final total = (milliseconds < 0 ? 0 : milliseconds) ~/ 1000;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = (total % 60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds' : '$minutes:$seconds';
}

/// Reads what [formatPosition] writes (`1:23`, `0:05`, `1:02:03`), or a plain number of seconds (`83`).
/// Returns milliseconds, or null when the text is not a time.
int? parsePosition(String text) {
  final parts = text.trim().split(':');
  if (parts.isEmpty || parts.length > 3 || parts.any((p) => p.isEmpty || int.tryParse(p) == null)) return null;
  final numbers = parts.map(int.parse).toList();
  if (numbers.any((n) => n < 0)) return null;
  // In m:ss and h:mm:ss the parts after the first one are below 60.
  if (numbers.length > 1 && numbers.skip(1).any((n) => n > 59)) return null;
  final seconds = switch (numbers.length) {
    1 => numbers[0],
    2 => numbers[0] * 60 + numbers[1],
    _ => numbers[0] * 3600 + numbers[1] * 60 + numbers[2],
  };
  return seconds * 1000;
}

/// A count for a label: `999`, `1,2K`, `12K`, `1,5M` (a comma for the decimals, as in Vietnamese).
String formatCount(int count) {
  String short(double value, String suffix) {
    final rounded = value >= 10 ? value.round().toString() : value.toStringAsFixed(1).replaceAll('.', ',');
    return '${rounded.endsWith(',0') ? rounded.substring(0, rounded.length - 2) : rounded}$suffix';
  }

  if (count < 1000) return '$count';
  if (count < 1000000) return short(count / 1000, 'K');
  return short(count / 1000000, 'M');
}
