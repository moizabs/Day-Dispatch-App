bool isDayDispatchUrl(Uri uri) =>
    uri.scheme == 'https' &&
    (uri.host == 'www.daydispatch.com' || uri.host == 'daydispatch.com') &&
    uri.userInfo.isEmpty &&
    uri.port == 443;

bool isExternalAccountPage(Uri uri) {
  if (!isDayDispatchUrl(uri)) return false;
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '').toLowerCase();
  return path == '/register' ||
      path == '/authentication/register-user' ||
      path.startsWith('/authentication/register-user/') ||
      path == '/authorized/number-of-login' ||
      path == '/authenticate/seat-plans-pricing' ||
      path == '/authorized/billing_subscription';
}
