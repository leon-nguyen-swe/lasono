/// "850 KB", "4,2 MB": the size of a file for a person. Uses a comma for the decimal, like the Vietnamese text around it.
String formatFileSize(int bytes) {
  const kb = 1024;
  const mb = 1024 * 1024;
  if (bytes < kb) return '$bytes B';
  if (bytes < mb) return '${(bytes / kb).round()} KB';
  final value = bytes / mb;
  final text = value >= 100 ? value.round().toString() : value.toStringAsFixed(1).replaceAll('.', ',');
  return '$text MB';
}
