// The 67 lower-case Vietnamese letters that carry a mark, and the plain letter each one stands for.
const _marked = 'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ';
final _plain = '${'a' * 17}${'e' * 11}${'i' * 5}${'o' * 17}${'u' * 11}${'y' * 5}d';

final Map<int, String> _fold = {
  for (var i = 0; i < _marked.runes.length; i++) _marked.runes.elementAt(i): _plain[i],
};

// A mark written as a separate character after its letter (the "decomposed" form some keyboards and files use).
final _combiningMarks = RegExp('[̀-ͯ]');

/// Lower-cases [text] and takes the marks off its letters: `Sơn Tùng` becomes `son tung`, `Đen Vâu` becomes
/// `den vau`. Both the one-character form (ơ) and the letter-plus-mark form (o + ̛ ) give the same result.
///
/// This is what lets a search without marks find a title with them. The backend does the same with
/// PostgreSQL's `unaccent` (see docs/backend-guide/06-search-vietnamese.md); the fake search uses this.
String foldAccents(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().replaceAll(_combiningMarks, '').runes) {
    buffer.write(_fold[rune] ?? String.fromCharCode(rune));
  }
  return buffer.toString();
}
