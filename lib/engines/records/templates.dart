import '../pdf/text_to_pdf.dart';
import 'autofill_profile.dart';

/// Feature 101 — Templates.
///
/// Ten everyday documents (resume, letters, rent receipt, invoice, NOC…)
/// in English and Hindi. Fields that the saved profile (096) knows — name,
/// phone, email, address, city, date of birth, today's date — are filled
/// in first; the rest are typed. The filled text goes through Text to PDF
/// (024), which shapes Devanagari with the phone's own fonts. Nothing
/// leaves the phone.

enum TemplateLang {
  en('English'),
  hi('हिन्दी');

  const TemplateLang(this.label);
  final String label;
}

/// Where a field's first value comes from.
enum ProfileSource { name, phone, email, address, city, dateOfBirth, today }

class TemplateField {
  const TemplateField(this.key, this.en, this.hi, {this.source, this.multiline = false});

  final String key;
  final String en;
  final String hi;
  final ProfileSource? source;
  final bool multiline;

  String label(TemplateLang l) => l == TemplateLang.en ? en : hi;
}

class DocTemplate {
  const DocTemplate({
    required this.id,
    required this.titleEn,
    required this.titleHi,
    required this.fields,
    required this.bodyEn,
    required this.bodyHi,
  });

  final String id;
  final String titleEn;
  final String titleHi;
  final List<TemplateField> fields;

  /// Text with `{key}` placeholders, one per field.
  final String bodyEn;
  final String bodyHi;

  String title(TemplateLang l) => l == TemplateLang.en ? titleEn : titleHi;
  String body(TemplateLang l) => l == TemplateLang.en ? bodyEn : bodyHi;
}

abstract final class Templates {
  static const String blank = '__________';

  static const TemplateField _name = TemplateField('name', 'Your name', 'आपका नाम', source: ProfileSource.name);
  static const TemplateField _address = TemplateField('address', 'Your address', 'आपका पता', source: ProfileSource.address, multiline: true);
  static const TemplateField _phone = TemplateField('phone', 'Phone', 'फ़ोन', source: ProfileSource.phone);
  static const TemplateField _email = TemplateField('email', 'Email', 'ईमेल', source: ProfileSource.email);
  static const TemplateField _date = TemplateField('date', 'Date', 'तारीख़', source: ProfileSource.today);
  static const TemplateField _place = TemplateField('place', 'Place', 'स्थान', source: ProfileSource.city);

  static const List<DocTemplate> all = <DocTemplate>[
    DocTemplate(
      id: 'resume',
      titleEn: 'Resume',
      titleHi: 'बायोडाटा',
      fields: <TemplateField>[
        _name,
        _phone,
        _email,
        _address,
        TemplateField('dob', 'Date of birth', 'जन्म तिथि', source: ProfileSource.dateOfBirth),
        TemplateField('objective', 'Objective', 'उद्देश्य', multiline: true),
        TemplateField('education', 'Education', 'शिक्षा', multiline: true),
        TemplateField('experience', 'Work experience', 'कार्य अनुभव', multiline: true),
        TemplateField('skills', 'Skills', 'कौशल', multiline: true),
        TemplateField('languages', 'Languages known', 'भाषाएँ'),
      ],
      bodyEn: '{name}\n{phone} · {email}\n{address}\n\nDate of birth: {dob}\n\nOBJECTIVE\n{objective}\n\nEDUCATION\n{education}\n\n'
          'WORK EXPERIENCE\n{experience}\n\nSKILLS\n{skills}\n\nLANGUAGES\n{languages}\n',
      bodyHi: '{name}\n{phone} · {email}\n{address}\n\nजन्म तिथि: {dob}\n\nउद्देश्य\n{objective}\n\nशिक्षा\n{education}\n\n'
          'कार्य अनुभव\n{experience}\n\nकौशल\n{skills}\n\nभाषाएँ\n{languages}\n',
    ),
    DocTemplate(
      id: 'rent-receipt',
      titleEn: 'Rent receipt',
      titleHi: 'किराया रसीद',
      fields: <TemplateField>[
        TemplateField('landlord', 'Landlord name', 'मकान मालिक का नाम'),
        TemplateField('tenant', 'Tenant name', 'किरायेदार का नाम', source: ProfileSource.name),
        TemplateField('property', 'Property address', 'मकान का पता', source: ProfileSource.address, multiline: true),
        TemplateField('amount', 'Rent (₹)', 'किराया (₹)'),
        TemplateField('month', 'For the month of', 'महीना'),
        TemplateField('mode', 'Paid by', 'भुगतान का तरीका'),
        TemplateField('pan', 'Landlord PAN (if rent over ₹1 lakh a year)', 'मकान मालिक का PAN (यदि सालाना किराया ₹1 लाख से अधिक)'),
        _date,
      ],
      bodyEn: 'RENT RECEIPT\n\nReceived from {tenant} the sum of ₹{amount} towards rent for {month} for the property at:\n{property}\n\n'
          'Paid by: {mode}\nDate: {date}\n\nLandlord: {landlord}\nPAN: {pan}\n\nSignature: {blank}\n',
      bodyHi: 'किराया रसीद\n\n{tenant} से {month} माह के किराये के रूप में ₹{amount} प्राप्त हुए, मकान का पता:\n{property}\n\n'
          'भुगतान का तरीका: {mode}\nतारीख़: {date}\n\nमकान मालिक: {landlord}\nPAN: {pan}\n\nहस्ताक्षर: {blank}\n',
    ),
    DocTemplate(
      id: 'invoice',
      titleEn: 'Invoice',
      titleHi: 'बिल (इनवॉइस)',
      fields: <TemplateField>[
        TemplateField('from', 'From (your name or business)', 'भेजने वाला (आपका नाम या व्यवसाय)', source: ProfileSource.name),
        TemplateField('fromAddress', 'Your address', 'आपका पता', source: ProfileSource.address, multiline: true),
        _phone,
        TemplateField('number', 'Invoice number', 'बिल संख्या'),
        _date,
        TemplateField('to', 'Bill to', 'किसको'),
        TemplateField('items', 'Items (one per line: item — amount)', 'सामान (हर पंक्ति में: सामान — राशि)', multiline: true),
        TemplateField('total', 'Total (₹)', 'कुल (₹)'),
        TemplateField('payment', 'Payment details (UPI or bank)', 'भुगतान विवरण (UPI या बैंक)'),
      ],
      bodyEn: 'INVOICE {number}\nDate: {date}\n\nFrom:\n{from}\n{fromAddress}\nPhone: {phone}\n\nBill to:\n{to}\n\n'
          'Items:\n{items}\n\nTotal: ₹{total}\n\nPayment: {payment}\n\nThank you.\n',
      bodyHi: 'बिल संख्या {number}\nतारीख़: {date}\n\nभेजने वाला:\n{from}\n{fromAddress}\nफ़ोन: {phone}\n\nकिसको:\n{to}\n\n'
          'सामान:\n{items}\n\nकुल: ₹{total}\n\nभुगतान: {payment}\n\nधन्यवाद।\n',
    ),
    DocTemplate(
      id: 'noc',
      titleEn: 'No objection certificate',
      titleHi: 'अनापत्ति प्रमाण पत्र',
      fields: <TemplateField>[
        _name,
        _address,
        TemplateField('person', 'Issued for (name)', 'किसके लिए (नाम)'),
        TemplateField('relation', 'Their relation to you', 'आपसे संबंध'),
        TemplateField('purpose', 'Purpose', 'उद्देश्य', multiline: true),
        _place,
        _date,
      ],
      bodyEn: 'NO OBJECTION CERTIFICATE\n\nTo whom it may concern,\n\nI, {name}, residing at {address}, have no objection to '
          '{person} ({relation}) for the following purpose:\n{purpose}\n\nPlace: {place}\nDate: {date}\n\n{name}\nSignature: {blank}\n',
      bodyHi: 'अनापत्ति प्रमाण पत्र\n\nजिसके लिए भी लागू हो,\n\nमैं, {name}, निवासी {address}, को {person} ({relation}) के '
          'निम्नलिखित उद्देश्य के लिए कोई आपत्ति नहीं है:\n{purpose}\n\nस्थान: {place}\nतारीख़: {date}\n\n{name}\nहस्ताक्षर: {blank}\n',
    ),
    DocTemplate(
      id: 'leave',
      titleEn: 'Leave application',
      titleHi: 'अवकाश प्रार्थना पत्र',
      fields: <TemplateField>[
        TemplateField('to', 'To (designation and office or school)', 'सेवा में (पद और कार्यालय या विद्यालय)', multiline: true),
        _name,
        TemplateField('role', 'Your class or designation', 'आपकी कक्षा या पद'),
        TemplateField('from', 'Leave from', 'छुट्टी कब से'),
        TemplateField('until', 'Leave until', 'छुट्टी कब तक'),
        TemplateField('reason', 'Reason', 'कारण', multiline: true),
        _date,
      ],
      bodyEn: 'To,\n{to}\n\nDate: {date}\n\nSubject: Application for leave\n\nRespected Sir/Madam,\n\nI, {name} ({role}), request leave '
          'from {from} to {until} because {reason}.\n\nKindly grant me leave for these days.\n\nYours faithfully,\n{name}\n',
      bodyHi: 'सेवा में,\n{to}\n\nतारीख़: {date}\n\nविषय: अवकाश हेतु प्रार्थना पत्र\n\nमहोदय/महोदया,\n\nमैं, {name} ({role}), {from} से '
          '{until} तक अवकाश का अनुरोध करता/करती हूँ, क्योंकि {reason}।\n\nकृपया इन दिनों का अवकाश स्वीकृत करें।\n\nभवदीय,\n{name}\n',
    ),
    DocTemplate(
      id: 'authority',
      titleEn: 'Authority letter',
      titleHi: 'प्राधिकार पत्र',
      fields: <TemplateField>[
        TemplateField('to', 'To (bank, office or school)', 'सेवा में (बैंक, कार्यालय या विद्यालय)', multiline: true),
        _name,
        _address,
        TemplateField('person', 'Person you authorise', 'अधिकृत व्यक्ति का नाम'),
        TemplateField('idProof', 'Their ID proof', 'उनका पहचान पत्र'),
        TemplateField('task', 'What they may do for you', 'वे आपकी ओर से क्या कर सकते हैं', multiline: true),
        _date,
      ],
      bodyEn: 'To,\n{to}\n\nDate: {date}\n\nSubject: Letter of authority\n\nI, {name}, residing at {address}, authorise {person} '
          '(ID: {idProof}) to {task} on my behalf.\n\nPlease treat their signature below as valid for this purpose.\n\n'
          'Signature of {person}: {blank}\n\nYours faithfully,\n{name}\nSignature: {blank}\n',
      bodyHi: 'सेवा में,\n{to}\n\nतारीख़: {date}\n\nविषय: प्राधिकार पत्र\n\nमैं, {name}, निवासी {address}, {person} '
          '(पहचान: {idProof}) को मेरी ओर से {task} के लिए अधिकृत करता/करती हूँ।\n\nकृपया इस कार्य के लिए नीचे दिए उनके हस्ताक्षर मान्य करें।\n\n'
          '{person} के हस्ताक्षर: {blank}\n\nभवदीय,\n{name}\nहस्ताक्षर: {blank}\n',
    ),
    DocTemplate(
      id: 'complaint',
      titleEn: 'Complaint letter',
      titleHi: 'शिकायत पत्र',
      fields: <TemplateField>[
        TemplateField('to', 'To (company or office)', 'सेवा में (कंपनी या कार्यालय)', multiline: true),
        _name,
        _address,
        _phone,
        TemplateField('subject', 'Complaint about', 'शिकायत का विषय'),
        TemplateField('reference', 'Order, account or reference number', 'ऑर्डर, खाता या संदर्भ संख्या'),
        TemplateField('details', 'What happened', 'क्या हुआ', multiline: true),
        TemplateField('ask', 'What you want done', 'आप क्या चाहते हैं', multiline: true),
        _date,
      ],
      bodyEn: 'To,\n{to}\n\nDate: {date}\n\nSubject: Complaint about {subject} (ref. {reference})\n\nSir/Madam,\n\n{details}\n\n'
          'I request you to {ask}.\n\nYours sincerely,\n{name}\n{address}\nPhone: {phone}\n',
      bodyHi: 'सेवा में,\n{to}\n\nतारीख़: {date}\n\nविषय: {subject} के संबंध में शिकायत (संदर्भ {reference})\n\nमहोदय/महोदया,\n\n{details}\n\n'
          'आपसे अनुरोध है कि {ask}।\n\nभवदीय,\n{name}\n{address}\nफ़ोन: {phone}\n',
    ),
    DocTemplate(
      id: 'cover-letter',
      titleEn: 'Cover letter',
      titleHi: 'आवेदन पत्र (नौकरी)',
      fields: <TemplateField>[
        _name,
        _phone,
        _email,
        TemplateField('company', 'Company', 'कंपनी'),
        TemplateField('position', 'Position', 'पद'),
        TemplateField('why', 'Why you fit (experience, skills)', 'आप उपयुक्त क्यों हैं (अनुभव, कौशल)', multiline: true),
        _date,
      ],
      bodyEn: 'Date: {date}\n\nTo the Hiring Manager,\n{company}\n\nSubject: Application for {position}\n\nDear Sir/Madam,\n\n'
          'I would like to apply for the post of {position} at {company}. {why}\n\nI have attached my resume and would be glad '
          'to meet you.\n\nYours sincerely,\n{name}\n{phone} · {email}\n',
      bodyHi: 'तारीख़: {date}\n\nसेवा में,\nभर्ती प्रबंधक,\n{company}\n\nविषय: {position} पद हेतु आवेदन\n\nमहोदय/महोदया,\n\n'
          'मैं {company} में {position} पद के लिए आवेदन करना चाहता/चाहती हूँ। {why}\n\nमेरा बायोडाटा संलग्न है। आपसे मिलकर मुझे प्रसन्नता होगी।\n\n'
          'भवदीय,\n{name}\n{phone} · {email}\n',
    ),
    DocTemplate(
      id: 'self-declaration',
      titleEn: 'Self declaration',
      titleHi: 'स्व-घोषणा पत्र',
      fields: <TemplateField>[
        _name,
        TemplateField('guardian', 'Father’s or husband’s name', 'पिता या पति का नाम'),
        _address,
        TemplateField('statement', 'I declare that…', 'मैं घोषणा करता/करती हूँ कि…', multiline: true),
        _place,
        _date,
      ],
      bodyEn: 'SELF DECLARATION\n\nI, {name}, son/daughter/wife of {guardian}, residing at {address}, do hereby declare that '
          '{statement}\n\nThe above is true to the best of my knowledge.\n\nPlace: {place}\nDate: {date}\n\n{name}\nSignature: {blank}\n',
      bodyHi: 'स्व-घोषणा पत्र\n\nमैं, {name}, पुत्र/पुत्री/पत्नी {guardian}, निवासी {address}, घोषणा करता/करती हूँ कि '
          '{statement}\n\nउपरोक्त जानकारी मेरी जानकारी में सत्य है।\n\nस्थान: {place}\nतारीख़: {date}\n\n{name}\nहस्ताक्षर: {blank}\n',
    ),
    DocTemplate(
      id: 'address-change',
      titleEn: 'Address change request',
      titleHi: 'पता परिवर्तन हेतु पत्र',
      fields: <TemplateField>[
        TemplateField('to', 'To (bank or office, branch)', 'सेवा में (बैंक या कार्यालय, शाखा)', multiline: true),
        _name,
        TemplateField('account', 'Account or customer number', 'खाता या ग्राहक संख्या'),
        TemplateField('oldAddress', 'Old address', 'पुराना पता', multiline: true),
        TemplateField('newAddress', 'New address', 'नया पता', source: ProfileSource.address, multiline: true),
        _phone,
        _date,
      ],
      bodyEn: 'To,\n{to}\n\nDate: {date}\n\nSubject: Change of address for account {account}\n\nSir/Madam,\n\nPlease update my address '
          'in your records.\n\nOld address:\n{oldAddress}\n\nNew address:\n{newAddress}\n\nA copy of my address proof is attached.\n\n'
          'Yours faithfully,\n{name}\nPhone: {phone}\n',
      bodyHi: 'सेवा में,\n{to}\n\nतारीख़: {date}\n\nविषय: खाता {account} में पता परिवर्तन\n\nमहोदय/महोदया,\n\nकृपया अपने रिकॉर्ड में मेरा पता '
          'बदल दें।\n\nपुराना पता:\n{oldAddress}\n\nनया पता:\n{newAddress}\n\nपते का प्रमाण संलग्न है।\n\nभवदीय,\n{name}\nफ़ोन: {phone}\n',
    ),
  ];

  static DocTemplate? byId(String id) {
    for (final DocTemplate t in all) {
      if (t.id == id) {
        return t;
      }
    }
    return null;
  }

  static const List<String> _monthsEn = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String dateLabel(DateTime d) => '${d.day} ${_monthsEn[d.month - 1]} ${d.year}';

  /// What the profile knows for [source]; empty when it does not.
  static String fromProfile(ProfileSource source, AutofillProfile p, DateTime today) {
    final SavedAddress? home = p.addresses.isEmpty ? null : p.addresses.first;
    return switch (source) {
      ProfileSource.name => p.fullName,
      ProfileSource.phone => p.phone.trim(),
      ProfileSource.email => p.email.trim(),
      ProfileSource.address => home == null ? '' : home.multiLine,
      ProfileSource.city => home == null ? '' : home.city.trim(),
      ProfileSource.dateOfBirth => p.dateOfBirth == null ? '' : dateLabel(p.dateOfBirth!),
      ProfileSource.today => dateLabel(today),
    };
  }

  /// Starting values for every field of [t].
  static Map<String, String> prefill(DocTemplate t, AutofillProfile p, DateTime today) => <String, String>{
        for (final TemplateField f in t.fields) f.key: f.source == null ? '' : fromProfile(f.source!, p, today),
      };

  /// The document text; empty fields become a line to write on.
  static String fill(DocTemplate t, TemplateLang lang, Map<String, String> values) {
    return t.body(lang).replaceAllMapped(RegExp(r'\{([A-Za-z]+)\}'), (Match m) {
      final String v = (values[m.group(1)!] ?? '').trim();
      return v.isEmpty ? blank : v;
    });
  }

  static String fileName(DocTemplate t, TemplateLang lang, Map<String, String> values) {
    final String who = (values['name'] ?? values['tenant'] ?? values['from'] ?? '').trim().replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '').trim();
    final String base = '${t.titleEn}${lang == TemplateLang.hi ? ' (Hindi)' : ''}${who.isEmpty ? '' : ' - $who'}';
    return '$base.pdf';
  }

  /// Makes the PDF through Text to PDF (024).
  static Future<TextPdfResult> toPdf(
    DocTemplate t,
    TemplateLang lang,
    Map<String, String> values, {
    TextPdfMaker maker = const TextPdfMaker(),
    TextPdfOptions options = const TextPdfOptions(fontSize: 12),
  }) =>
      maker.make(fill(t, lang, values), options, name: fileName(t, lang, values));
}
