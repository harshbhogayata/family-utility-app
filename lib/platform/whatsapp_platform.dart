import 'package:url_launcher/url_launcher.dart';

import '../engines/records/whatsapp_direct.dart';

/// 102: hands the wa.me link to WhatsApp (or the browser if it is missing).
class UrlLinkOpener implements LinkOpener {
  const UrlLinkOpener();

  @override
  Future<bool> open(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
}
