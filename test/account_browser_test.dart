import 'package:daydispatch/account_browser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account pages open externally with plan and query parameters', () {
    for (final path in [
      '/register',
      '/Authentication/Register-User/12/Carrier?source=app',
      '/Authorized/number-of-login',
      '/Authenticate/seat-plans-pricing',
      '/Authorized/billing_subscription/',
    ]) {
      expect(
        isExternalAccountPage(Uri.parse('https://www.daydispatch.com$path')),
        isTrue,
      );
    }
  });

  test('other pages and untrusted destinations stay out of the launcher', () {
    for (final url in [
      'https://www.daydispatch.com/Authentication/Login-Form',
      'https://www.daydispatch.com/Authentication/Register-User-Submit',
      'https://evil.example/Authorized/billing_subscription',
      'https://daydispatch.com.evil.example/register',
      'http://daydispatch.com/register',
      'https://user@daydispatch.com/register',
      'https://daydispatch.com:444/register',
    ]) {
      expect(isExternalAccountPage(Uri.parse(url)), isFalse);
    }
  });
}
