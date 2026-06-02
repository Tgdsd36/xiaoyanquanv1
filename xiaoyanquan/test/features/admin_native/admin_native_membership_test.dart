import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoyanquan/features/admin_native/utils/admin_native_membership.dart';

void main() {
  group('native admin membership mapping', () {
    test('professional users show professional badge instead of free', () {
      expect(memberBadgeLabel('professional'), '专业版');
      expect(shouldShowMemberExpiry('professional'), isTrue);
    });

    test('free users keep free badge and hide expiry', () {
      expect(memberBadgeLabel('free'), 'Free');
      expect(shouldShowMemberExpiry('free'), isFalse);
    });

    test('pro-like users keep paid badge and expiry', () {
      expect(memberBadgeLabel('pro'), 'Pro');
      expect(memberBadgeLabel('flagship'), 'Pro');
      expect(shouldShowMemberExpiry('pro'), isTrue);
      expect(shouldShowMemberExpiry('flagship'), isTrue);
    });
  });
}
