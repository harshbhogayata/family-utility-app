import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/strings_scope.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/family/member_profiles.dart';
import '../../engines/platform/app_strings.dart';
import '../../engines/share/share_engine.dart';

typedef LanguageTextAction = Future<String?> Function(String text);

/// Feature 110 — pick the app language for the member using the phone now.
/// Each profile keeps its own choice; switching profile switches language.
class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key, this.profiles, this.share, this.save});

  final MemberProfiles? profiles;
  final LanguageTextAction? share;
  final LanguageTextAction? save;

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  MemberProfiles get _p => widget.profiles ?? MemberProfiles.instance;

  /// (profile id, language before the last change), for Undo.
  (String, String)? _before;

  String _describe() {
    final MemberProfile who = _p.active;
    return '${who.name}: ${AppStrings.forProfile(who).languageName}\n';
  }

  Future<void> _pick(String code) async {
    final MemberProfile who = _p.active;
    if (who.language == code) {
      return;
    }
    _before = (who.id, who.language);
    await _p.setLanguage(who.id, code);
    if (mounted) {
      final AppStrings t = AppStrings.forCode(code);
      _snack(t.get(StringKeys.languageChanged, <String, String>{'language': t.languageName}));
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  static Future<String?> _saveToDocuments(String text) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/Language.txt');
    await f.writeAsString(text);
    return f.path;
  }

  Future<void> _share() async {
    final LanguageTextAction? s = widget.share;
    if (s != null) {
      await s(_describe());
    } else {
      await ShareEngine.instance.shareText(_describe(), subject: 'App language');
    }
  }

  Future<void> _save() async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_describe());
    } catch (_) {
      where = null;
    }
    if (mounted) {
      final AppStrings t = AppStringsScope.of(context);
      _snack(where == null ? t.get(StringKeys.couldNotSave) : t.get(StringKeys.savedTo, <String, String>{'where': where}));
    }
  }

  Future<void> _undo() async {
    final (String, String)? b = _before;
    _before = null;
    if (b != null) {
      await _p.setLanguage(b.$1, b.$2);
    }
    if (mounted) {
      final AppStrings t = AppStringsScope.of(context);
      _snack(t.get(b == null ? StringKeys.nothingToUndo : StringKeys.undone));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _p,
      builder: (BuildContext context, Widget? _) {
        final MemberProfile who = _p.active;
        final AppStrings t = AppStringsScope.of(context);
        final TextTheme text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: Text(t.get(StringKeys.languageFor, <String, String>{'name': who.name}))),
          bottomNavigationBar: ResultBar(
            onShare: () => unawaited(_share()),
            onSave: () => unawaited(_save()),
            onUndo: () => unawaited(_undo()),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Each family member keeps their own language. Everything is in the app; '
                  'nothing is downloaded.',
                  style: text.bodyMedium,
                ),
              ),
              RadioGroup<String>(
                groupValue: who.language,
                onChanged: (String? c) {
                  if (c != null) {
                    unawaited(_pick(c));
                  }
                },
                child: Column(
                  children: <Widget>[
                    for (final String code in AppStrings.languages)
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 56),
                        child: RadioListTile<String>(
                          key: Key('language-$code'),
                          value: code,
                          title: Text(ProfileLanguages.nameOf(code)),
                          subtitle: Text(
                            '${AppStrings.forCode(code).tabTools} · ${AppStrings.forCode(code).tabFamily} · '
                            '${AppStrings.forCode(code).share}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
