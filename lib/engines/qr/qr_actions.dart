import 'qr_payload.dart';

/// What the result screen can do with a payload. The tool UI only talks to
/// this interface; the platform implementation lives in the tool folder and
/// tests use a fake. Nothing here ever sends the scan anywhere.
abstract class QrActions {
  /// Opens a link, tel:, mailto:, sms:, geo: or upi:// URI in the matching app.
  /// Returns false when no app can handle it.
  Future<bool> openUri(Uri uri);

  /// Joins the network described by the code. Returns false when the platform
  /// refused (then the UI offers the password to copy and the settings page).
  Future<bool> joinWifi(WifiPayload wifi);

  /// Saves a vCard to the device contacts. Returns false when permission was
  /// denied.
  Future<bool> saveContact(VCardPayload card);

  /// Hands an event to the calendar app.
  Future<bool> addEvent(EventPayload event);

  /// Share sheet with the plain text.
  Future<void> shareText(String text);

  /// Writes the text to the app's own folder; returns the saved path.
  Future<String> saveText(String fileName, String text);

  /// Removes a file written by [saveText] (Undo).
  Future<void> deleteSaved(String path);

  /// Copies text to the clipboard.
  Future<void> copyText(String text);
}
