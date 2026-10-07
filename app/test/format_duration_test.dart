import 'package:flutter_test/flutter_test.dart';

import 'package:lasono_app/format_duration.dart';

void main() {
  group('formatSeconds', () {
    test('shows dashes while the duration is not known', () {
      expect(formatSeconds(null), '--:--');
    });

    test('shows minutes and two-digit seconds', () {
      expect(formatSeconds(185), '3:05');
      expect(formatSeconds(0), '0:00');
    });

    test('drops the fraction, like the player does', () {
      expect(formatSeconds(185.9), '3:05');
      expect(formatSeconds(59.9), '0:59');
    });

    test('keeps counting minutes past an hour', () {
      expect(formatSeconds(3600), '60:00');
    });
  });
}
