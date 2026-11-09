import 'package:flutter/foundation.dart';

import '../family/member_profiles.dart';

/// Feature 110 — Indian languages per profile.
///
/// The app's shared strings (tabs, the Share / Save / Undo bar, tool
/// sections, common messages) live here, keyed, in seven languages:
/// English, Hindi, Tamil, Telugu, Bengali, Marathi and Gujarati. Each
/// member profile (feature 069) picks one; the UI follows the active
/// profile. Everything is bundled in the app: no download, no network.
/// A key missing in a language falls back to English, never to a blank.

abstract final class StringKeys {
  static const String tabTools = 'tab.tools';
  static const String tabFamily = 'tab.family';
  static const String tabRecords = 'tab.records';
  static const String tabFiles = 'tab.files';
  static const String share = 'action.share';
  static const String save = 'action.save';
  static const String undo = 'action.undo';
  static const String lastSharedTo = 'share.lastSharedTo';
  static const String language = 'language.title';
  static const String languageFor = 'language.for';
  static const String languageChanged = 'language.changed';
  static const String undone = 'message.undone';
  static const String nothingToUndo = 'message.nothingToUndo';
  static const String savedTo = 'message.savedTo';
  static const String couldNotSave = 'message.couldNotSave';
  static const String sectionPdf = 'section.pdf';
  static const String sectionConvert = 'section.convert';
  static const String sectionCompress = 'section.compress';
  static const String sectionImage = 'section.image';
  static const String sectionScan = 'section.scan';
  static const String sectionSecurity = 'section.security';
  static const String sectionShare = 'section.share';
  static const String sectionLinks = 'section.links';
  static const String sectionPlatform = 'section.platform';

  static const List<String> all = <String>[
    tabTools,
    tabFamily,
    tabRecords,
    tabFiles,
    share,
    save,
    undo,
    lastSharedTo,
    language,
    languageFor,
    languageChanged,
    undone,
    nothingToUndo,
    savedTo,
    couldNotSave,
    sectionPdf,
    sectionConvert,
    sectionCompress,
    sectionImage,
    sectionScan,
    sectionSecurity,
    sectionShare,
    sectionLinks,
    sectionPlatform,
  ];
}

const Map<String, String> _en = <String, String>{
  StringKeys.tabTools: 'Tools',
  StringKeys.tabFamily: 'Family',
  StringKeys.tabRecords: 'Records',
  StringKeys.tabFiles: 'Files',
  StringKeys.share: 'Share',
  StringKeys.save: 'Save',
  StringKeys.undo: 'Undo',
  StringKeys.lastSharedTo: 'Last shared to {names}',
  StringKeys.language: 'Language',
  StringKeys.languageFor: 'Language for {name}',
  StringKeys.languageChanged: 'The app now speaks {language}',
  StringKeys.undone: 'Undone',
  StringKeys.nothingToUndo: 'Nothing to undo',
  StringKeys.savedTo: 'Saved to {where}',
  StringKeys.couldNotSave: 'Could not save',
  StringKeys.sectionPdf: 'PDF',
  StringKeys.sectionConvert: 'Convert',
  StringKeys.sectionCompress: 'Compress',
  StringKeys.sectionImage: 'Images',
  StringKeys.sectionScan: 'Scan and QR',
  StringKeys.sectionSecurity: 'Security',
  StringKeys.sectionShare: 'Share and transfer',
  StringKeys.sectionLinks: 'Links',
  StringKeys.sectionPlatform: 'Platform',
};

const Map<String, String> _hi = <String, String>{
  StringKeys.tabTools: 'टूल्स',
  StringKeys.tabFamily: 'परिवार',
  StringKeys.tabRecords: 'रिकॉर्ड',
  StringKeys.tabFiles: 'फ़ाइलें',
  StringKeys.share: 'शेयर करें',
  StringKeys.save: 'सेव करें',
  StringKeys.undo: 'वापस लें',
  StringKeys.lastSharedTo: 'पिछली बार {names} पर शेयर किया',
  StringKeys.language: 'भाषा',
  StringKeys.languageFor: '{name} की भाषा',
  StringKeys.languageChanged: 'अब ऐप {language} में है',
  StringKeys.undone: 'वापस लिया गया',
  StringKeys.nothingToUndo: 'वापस लेने को कुछ नहीं',
  StringKeys.savedTo: '{where} में सेव किया गया',
  StringKeys.couldNotSave: 'सेव नहीं हो सका',
  StringKeys.sectionPdf: 'PDF',
  StringKeys.sectionConvert: 'बदलें',
  StringKeys.sectionCompress: 'छोटा करें',
  StringKeys.sectionImage: 'तस्वीरें',
  StringKeys.sectionScan: 'स्कैन और QR',
  StringKeys.sectionSecurity: 'सुरक्षा',
  StringKeys.sectionShare: 'शेयर और ट्रांसफ़र',
  StringKeys.sectionLinks: 'लिंक',
  StringKeys.sectionPlatform: 'प्लेटफ़ॉर्म',
};

const Map<String, String> _ta = <String, String>{
  StringKeys.tabTools: 'கருவிகள்',
  StringKeys.tabFamily: 'குடும்பம்',
  StringKeys.tabRecords: 'பதிவுகள்',
  StringKeys.tabFiles: 'கோப்புகள்',
  StringKeys.share: 'பகிர்',
  StringKeys.save: 'சேமி',
  StringKeys.undo: 'செயல்தவிர்',
  StringKeys.lastSharedTo: 'கடைசியாக {names} இல் பகிரப்பட்டது',
  StringKeys.language: 'மொழி',
  StringKeys.languageFor: '{name} இன் மொழி',
  StringKeys.languageChanged: 'இனி ஆப் {language} இல்',
  StringKeys.undone: 'செயல்தவிர்க்கப்பட்டது',
  StringKeys.nothingToUndo: 'செயல்தவிர்க்க எதுவும் இல்லை',
  StringKeys.savedTo: '{where} இல் சேமிக்கப்பட்டது',
  StringKeys.couldNotSave: 'சேமிக்க முடியவில்லை',
  StringKeys.sectionPdf: 'PDF',
  StringKeys.sectionConvert: 'மாற்று',
  StringKeys.sectionCompress: 'சுருக்கு',
  StringKeys.sectionImage: 'படங்கள்',
  StringKeys.sectionScan: 'ஸ்கேன் மற்றும் QR',
  StringKeys.sectionSecurity: 'பாதுகாப்பு',
  StringKeys.sectionShare: 'பகிர்வு மற்றும் பரிமாற்றம்',
  StringKeys.sectionLinks: 'இணைப்புகள்',
  StringKeys.sectionPlatform: 'தளம்',
};

const Map<String, String> _te = <String, String>{
  StringKeys.tabTools: 'టూల్స్',
  StringKeys.tabFamily: 'కుటుంబం',
  StringKeys.tabRecords: 'రికార్డులు',
  StringKeys.tabFiles: 'ఫైళ్లు',
  StringKeys.share: 'షేర్ చేయి',
  StringKeys.save: 'సేవ్ చేయి',
  StringKeys.undo: 'రద్దు చేయి',
  StringKeys.lastSharedTo: 'చివరిగా {names} కి షేర్ చేశారు',
  StringKeys.language: 'భాష',
  StringKeys.languageFor: '{name} భాష',
  StringKeys.languageChanged: 'ఇప్పుడు యాప్ {language} లో ఉంది',
  StringKeys.undone: 'రద్దు చేయబడింది',
  StringKeys.nothingToUndo: 'రద్దు చేయడానికి ఏమీ లేదు',
  StringKeys.savedTo: '{where} లో సేవ్ చేయబడింది',
  StringKeys.couldNotSave: 'సేవ్ చేయలేకపోయాం',
  StringKeys.sectionPdf: 'PDF',
  StringKeys.sectionConvert: 'మార్చు',
  StringKeys.sectionCompress: 'కుదించు',
  StringKeys.sectionImage: 'చిత్రాలు',
  StringKeys.sectionScan: 'స్కాన్ మరియు QR',
  StringKeys.sectionSecurity: 'భద్రత',
  StringKeys.sectionShare: 'షేర్ మరియు బదిలీ',
  StringKeys.sectionLinks: 'లింక్‌లు',
  StringKeys.sectionPlatform: 'ప్లాట్‌ఫారమ్',
};

const Map<String, String> _bn = <String, String>{
  StringKeys.tabTools: 'টুলস',
  StringKeys.tabFamily: 'পরিবার',
  StringKeys.tabRecords: 'রেকর্ড',
  StringKeys.tabFiles: 'ফাইল',
  StringKeys.share: 'শেয়ার করুন',
  StringKeys.save: 'সেভ করুন',
  StringKeys.undo: 'আগের মতো করুন',
  StringKeys.lastSharedTo: 'শেষবার {names}-এ শেয়ার করা হয়েছে',
  StringKeys.language: 'ভাষা',
  StringKeys.languageFor: '{name}-এর ভাষা',
  StringKeys.languageChanged: 'এখন অ্যাপ {language}-এ',
  StringKeys.undone: 'আগের মতো করা হয়েছে',
  StringKeys.nothingToUndo: 'ফেরানোর মতো কিছু নেই',
  StringKeys.savedTo: '{where}-এ সেভ হয়েছে',
  StringKeys.couldNotSave: 'সেভ করা গেল না',
  StringKeys.sectionPdf: 'PDF',
  StringKeys.sectionConvert: 'রূপান্তর',
  StringKeys.sectionCompress: 'ছোট করুন',
  StringKeys.sectionImage: 'ছবি',
  StringKeys.sectionScan: 'স্ক্যান ও QR',
  StringKeys.sectionSecurity: 'নিরাপত্তা',
  StringKeys.sectionShare: 'শেয়ার ও ট্রান্সফার',
  StringKeys.sectionLinks: 'লিংক',
  StringKeys.sectionPlatform: 'প্ল্যাটফর্ম',
};

const Map<String, String> _mr = <String, String>{
  StringKeys.tabTools: 'साधने',
  StringKeys.tabFamily: 'कुटुंब',
  StringKeys.tabRecords: 'नोंदी',
  StringKeys.tabFiles: 'फाइल्स',
  StringKeys.share: 'शेअर करा',
  StringKeys.save: 'सेव्ह करा',
  StringKeys.undo: 'पूर्ववत करा',
  StringKeys.lastSharedTo: 'शेवटचे {names} वर शेअर केले',
  StringKeys.language: 'भाषा',
  StringKeys.languageFor: '{name} ची भाषा',
  StringKeys.languageChanged: 'आता अ‍ॅप {language} मध्ये आहे',
  StringKeys.undone: 'पूर्ववत केले',
  StringKeys.nothingToUndo: 'पूर्ववत करण्यासारखे काही नाही',
  StringKeys.savedTo: '{where} मध्ये सेव्ह केले',
  StringKeys.couldNotSave: 'सेव्ह करता आले नाही',
  StringKeys.sectionPdf: 'PDF',
  StringKeys.sectionConvert: 'रूपांतर',
  StringKeys.sectionCompress: 'लहान करा',
  StringKeys.sectionImage: 'चित्रे',
  StringKeys.sectionScan: 'स्कॅन आणि QR',
  StringKeys.sectionSecurity: 'सुरक्षा',
  StringKeys.sectionShare: 'शेअर आणि ट्रान्सफर',
  StringKeys.sectionLinks: 'लिंक्स',
  StringKeys.sectionPlatform: 'प्लॅटफॉर्म',
};

const Map<String, String> _gu = <String, String>{
  StringKeys.tabTools: 'સાધનો',
  StringKeys.tabFamily: 'પરિવાર',
  StringKeys.tabRecords: 'રેકોર્ડ્સ',
  StringKeys.tabFiles: 'ફાઇલો',
  StringKeys.share: 'શેર કરો',
  StringKeys.save: 'સેવ કરો',
  StringKeys.undo: 'પૂર્વવત્ કરો',
  StringKeys.lastSharedTo: 'છેલ્લે {names} પર શેર કર્યું',
  StringKeys.language: 'ભાષા',
  StringKeys.languageFor: '{name} ની ભાષા',
  StringKeys.languageChanged: 'હવે એપ {language} માં છે',
  StringKeys.undone: 'પૂર્વવત્ કર્યું',
  StringKeys.nothingToUndo: 'પૂર્વવત્ કરવા માટે કંઈ નથી',
  StringKeys.savedTo: '{where} માં સેવ કર્યું',
  StringKeys.couldNotSave: 'સેવ થઈ શક્યું નહીં',
  StringKeys.sectionPdf: 'PDF',
  StringKeys.sectionConvert: 'રૂપાંતર',
  StringKeys.sectionCompress: 'નાનું કરો',
  StringKeys.sectionImage: 'છબીઓ',
  StringKeys.sectionScan: 'સ્કેન અને QR',
  StringKeys.sectionSecurity: 'સુરક્ષા',
  StringKeys.sectionShare: 'શેર અને ટ્રાન્સફર',
  StringKeys.sectionLinks: 'લિંક્સ',
  StringKeys.sectionPlatform: 'પ્લેટફોર્મ',
};

@immutable
class AppStrings {
  const AppStrings._(this.code, this._table);

  /// The language code, one of [ProfileLanguages.names].
  final String code;
  final Map<String, String> _table;

  static const Map<String, Map<String, String>> catalog = <String, Map<String, String>>{
    'en': _en,
    'hi': _hi,
    'ta': _ta,
    'te': _te,
    'bn': _bn,
    'mr': _mr,
    'gu': _gu,
  };

  static const AppStrings english = AppStrings._('en', _en);

  static List<String> get languages => catalog.keys.toList();

  /// Strings for [code]; an unknown code gives English.
  static AppStrings forCode(String code) {
    final Map<String, String>? t = catalog[code];
    return t == null ? english : AppStrings._(code, t);
  }

  static AppStrings forProfile(MemberProfile p) => forCode(p.language);

  /// The string for [key], with `{name}` placeholders filled from [args].
  /// Falls back to English, then to the key itself.
  String get(String key, [Map<String, String> args = const <String, String>{}]) {
    String s = _table[key] ?? _en[key] ?? key;
    args.forEach((String k, String v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  String get tabTools => get(StringKeys.tabTools);
  String get tabFamily => get(StringKeys.tabFamily);
  String get tabRecords => get(StringKeys.tabRecords);
  String get tabFiles => get(StringKeys.tabFiles);
  String get share => get(StringKeys.share);
  String get save => get(StringKeys.save);
  String get undo => get(StringKeys.undo);
  String lastSharedTo(String names) => get(StringKeys.lastSharedTo, <String, String>{'names': names});

  /// The language's own name, e.g. "தமிழ் (Tamil)".
  String get languageName => ProfileLanguages.nameOf(code);

  /// Keys this language does not translate (English fallback is used).
  static List<String> missingKeys(String code) {
    final Map<String, String> t = catalog[code] ?? const <String, String>{};
    return StringKeys.all.where((String k) => (t[k] ?? '').trim().isEmpty).toList();
  }

  /// Placeholders like `{name}` in [s], in order.
  static List<String> placeholders(String s) =>
      RegExp(r'\{(\w+)\}').allMatches(s).map((RegExpMatch m) => m.group(1)!).toList();
}
