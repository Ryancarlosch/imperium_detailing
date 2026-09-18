class ImperiumAppLinks {
  const ImperiumAppLinks._();

  static const String scheme = 'imperiumdetailing';
  static const String loginHost = 'login-callback';
  static const String paymentHost = 'payment-return';

  static const String loginCallback = '$scheme://$loginHost/';
  static const String paymentReturn = '$scheme://$paymentHost/';
}
