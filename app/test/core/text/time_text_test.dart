import 'package:flutter_test/flutter_test.dart';
import 'package:lasono_app/core/text/time_text.dart';

final _now = DateTime.utc(2026, 10, 8, 12);

String _ago(Duration age) => relativeTime(_now.subtract(age), now: _now);

void main() {
  group('relativeTime', () {
    test('just now: under 45 seconds, and a time a little in the future', () {
      expect(_ago(Duration.zero), 'vừa xong');
      expect(_ago(const Duration(seconds: 44)), 'vừa xong');
      expect(relativeTime(_now.add(const Duration(minutes: 3)), now: _now), 'vừa xong');
    });

    test('minutes, from the first one to the last before an hour', () {
      expect(_ago(const Duration(seconds: 45)), '1 phút trước');
      expect(_ago(const Duration(minutes: 5)), '5 phút trước');
      expect(_ago(const Duration(minutes: 59, seconds: 59)), '59 phút trước');
    });

    test('hours', () {
      expect(_ago(const Duration(hours: 1)), '1 giờ trước');
      expect(_ago(const Duration(hours: 23, minutes: 59)), '23 giờ trước');
    });

    test('days', () {
      expect(_ago(const Duration(days: 1)), '1 ngày trước');
      expect(_ago(const Duration(days: 3, hours: 5)), '3 ngày trước');
      expect(_ago(const Duration(days: 6, hours: 23)), '6 ngày trước');
    });

    test('weeks', () {
      expect(_ago(const Duration(days: 7)), '1 tuần trước');
      expect(_ago(const Duration(days: 20)), '2 tuần trước');
      expect(_ago(const Duration(days: 29)), '4 tuần trước');
    });

    test('months and years', () {
      expect(_ago(const Duration(days: 30)), '1 tháng trước');
      expect(_ago(const Duration(days: 200)), '6 tháng trước');
      expect(_ago(const Duration(days: 364)), '12 tháng trước');
      expect(_ago(const Duration(days: 365)), '1 năm trước');
      expect(_ago(const Duration(days: 800)), '2 năm trước');
    });

    test('does not depend on the time zone the date was given in', () {
      final local = DateTime.utc(2026, 10, 8, 9).toLocal();
      expect(relativeTime(local, now: _now), '3 giờ trước');
    });
  });

  group('formatPosition', () {
    test('minutes and seconds, the seconds always with two digits', () {
      expect(formatPosition(0), '0:00');
      expect(formatPosition(5000), '0:05');
      expect(formatPosition(83000), '1:23');
      expect(formatPosition(213400), '3:33');
    });

    test('cuts the milliseconds, it does not round up to the next second', () {
      expect(formatPosition(59999), '0:59');
    });

    test('hours when there are some', () {
      expect(formatPosition(3600000), '1:00:00');
      expect(formatPosition(3723000), '1:02:03');
    });

    test('a negative position is zero', () {
      expect(formatPosition(-500), '0:00');
    });
  });

  group('parsePosition', () {
    test('reads what formatPosition writes', () {
      for (final ms in [0, 5000, 83000, 213000, 3723000]) {
        expect(parsePosition(formatPosition(ms)), ms);
      }
    });

    test('reads a plain number of seconds, and ignores the spaces around', () {
      expect(parsePosition('83'), 83000);
      expect(parsePosition('  1:23 '), 83000);
    });

    test('refuses what is not a time', () {
      for (final text in ['', 'abc', '1:', ':30', '1:2x', '1:60', '1:2:3:4', '-5', '1:-5', '1.5']) {
        expect(parsePosition(text), isNull, reason: '"$text"');
      }
    });
  });

  group('formatCount', () {
    test('writes small numbers as they are', () {
      expect(formatCount(0), '0');
      expect(formatCount(7), '7');
      expect(formatCount(999), '999');
    });

    test('thousands with one decimal below ten thousand, none above', () {
      expect(formatCount(1000), '1K');
      expect(formatCount(1200), '1,2K');
      expect(formatCount(9999), '10K');
      expect(formatCount(12345), '12K');
      expect(formatCount(999999), '1000K');
    });

    test('millions', () {
      expect(formatCount(1000000), '1M');
      expect(formatCount(1500000), '1,5M');
      expect(formatCount(25000000), '25M');
    });
  });
}
