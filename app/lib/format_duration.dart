/// Shows a duration in seconds as `minutes:seconds`, or `--:--` when it is not known yet
/// (a track that is still being processed).
String formatSeconds(double? seconds) {
  if (seconds == null) return '--:--';
  final whole = seconds.floor();
  final secondsPart = (whole % 60).toString().padLeft(2, '0');
  return '${whole ~/ 60}:$secondsPart';
}
