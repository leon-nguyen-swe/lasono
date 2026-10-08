import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/core/text/fold_accents.dart';

void main() {
  test('takes the marks off Vietnamese letters and lower-cases them', () {
    expect(foldAccents('Sơn Tùng M-TP'), 'son tung m-tp');
    expect(foldAccents('Nắng ấm xa dần'), 'nang am xa dan');
    expect(foldAccents('Đen Vâu'), 'den vau');
    expect(foldAccents('Hà Anh Tuấn - Tháng Tư là lời nói dối của em'), 'ha anh tuan - thang tu la loi noi doi cua em');
  });

  test('every Vietnamese letter with every tone folds to its plain letter', () {
    const expected = {
      'àáảãạăằắẳẵặâầấẩẫậ': 'a',
      'èéẻẽẹêềếểễệ': 'e',
      'ìíỉĩị': 'i',
      'òóỏõọôồốổỗộơờớởỡợ': 'o',
      'ùúủũụưừứửữự': 'u',
      'ỳýỷỹỵ': 'y',
      'đ': 'd',
    };
    for (final entry in expected.entries) {
      for (final letter in entry.key.runes.map(String.fromCharCode)) {
        expect(foldAccents(letter), entry.value, reason: '$letter should fold to ${entry.value}');
        expect(foldAccents(letter.toUpperCase()), entry.value, reason: '${letter.toUpperCase()} should too');
      }
    }
  });

  test('a letter written as base + separate mark folds like the one-character letter', () {
    const decomposed = 'Sơn Tùng'; // o + horn, u + grave
    expect(foldAccents(decomposed), 'son tung');
    expect(foldAccents(decomposed), foldAccents('Sơn Tùng'));
  });

  test('leaves plain text, digits and punctuation alone', () {
    expect(foldAccents('Lo-fi for Rainy Days 2026!'), 'lo-fi for rainy days 2026!');
    expect(foldAccents(''), '');
  });

  test('folding twice changes nothing more', () {
    final once = foldAccents('Bích Phương - Bùa yêu');
    expect(foldAccents(once), once);
  });

  test('two spellings of the same name fold to the same text, which is what search relies on', () {
    expect(foldAccents('SƠN TÙNG'), foldAccents('son tung'));
  });
}
