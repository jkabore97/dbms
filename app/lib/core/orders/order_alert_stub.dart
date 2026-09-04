/// The quiet half of the doorbell: everywhere that is not a browser.
///
/// On Android the app in the foreground already shows the badge and the
/// in-app line; a notification the OS carries while the app is closed needs
/// FCM, which is infrastructure this build does not have — so here the
/// doorbell honestly does not exist rather than pretending.
class OrderAlertPlatform {
  const OrderAlertPlatform._();

  static bool get supported => false;
  static bool get granted => false;
  static Future<bool> request() async => false;
  static void show(String title, String body) {}
}
