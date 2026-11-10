import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/records/subscriptions.dart';
import 'package:family_utility_app/records/subscriptions/subscriptions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

class RecordingReminders implements SubscriptionReminderScheduler {
  List<SubscriptionReminder> last = <SubscriptionReminder>[];
  @override
  Future<void> replaceAll(List<SubscriptionReminder> reminders) async => last = reminders;
}

Subscriptions make({SubscriptionReminderScheduler? reminders}) => Subscriptions(
      space: newSpace(),
      soloStore: FamilyStore(deviceId: 'me'),
      reminders: reminders ?? const NoSubscriptionReminders(),
      now: () => DateTime(2026, 1, 20, 10),
    );

void main() {
  group('engine', () {
    test('reminders before renewal and trial end; yearly total; renew; cancel and undo', () async {
      final RecordingReminders rec = RecordingReminders();
      final Subscriptions s = make(reminders: rec);
      expect(s.add(name: ' ', paise: 100, renews: DateTime(2026, 2, 1)), isNull);
      expect(s.add(name: 'X', paise: 100, renews: DateTime(2026, 2, 1), everyMonths: 2), isNull);
      final Subscription netflix = s.add(name: 'Netflix', paise: 64900, renews: DateTime(2026, 1, 25))!;
      final Subscription prime = s.add(name: 'Prime', paise: 149900, renews: DateTime(2026, 1, 30), everyMonths: 12, trial: true)!;
      await Future<void>.delayed(Duration.zero);
      expect(rec.last.map((SubscriptionReminder r) => (r.title, r.at)).toList(), <(String, DateTime)>[
        ('Netflix renews in 3 days', DateTime(2026, 1, 22, 9)),
        ('Prime free trial ends in 3 days', DateTime(2026, 1, 27, 9)),
        ('Prime free trial ends tomorrow', DateTime(2026, 1, 29, 9)),
      ]);
      expect(rec.last.first.body, startsWith('₹649 will be charged'));

      expect(netflix.perYear, 778800);
      expect(s.yearlyTotal, 928700);
      expect(s.monthlyAverage, 77391);

      expect(s.renew(netflix.id), isTrue);
      expect(s.byId(netflix.id)!.renews, DateTime(2026, 2, 25));
      expect(s.renew(prime.id), isTrue);
      expect(s.byId(prime.id)!.trial, isFalse);
      expect(s.byId(prime.id)!.renews, DateTime(2027, 1, 30));

      expect(s.cancel(netflix.id), isTrue);
      expect(s.yearlyTotal, 149900);
      expect(s.undo(), isTrue);
      expect(s.yearlyTotal, 928700);
      expect(s.toText(), contains('- Netflix: ₹649 / month, renews 25 Feb 2026 (₹7,788 a year)'));
      expect(s.toText(), endsWith('Total ₹9,287 a year\n'));
    });

    test('shared with the family', () async {
      final FamilySpace a = newSpace();
      await a.create(familyName: 'Shahs', memberName: 'Asha');
      Subscriptions(space: a, now: () => DateTime(2026, 1, 20)).add(name: 'Hotstar', paise: 29900, renews: DateTime(2026, 2, 1), everyMonths: 3);
      final FamilySpace b = newSpace();
      await b.create(familyName: 'x', memberName: 'Ravi');
      b.store.mergeAll(a.store.allRecords);
      expect(Subscriptions(space: b, now: () => DateTime(2026, 1, 20)).all.single.perYear, 119600);
    });
  });

  testWidgets('screen: add subscription, yearly total, renew, share, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final Subscriptions s = make();
    final List<String> shared = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: SubscriptionsScreen(subscriptions: s, share: (String t) async => shared.add(t), save: (String t, String n) async => '/x/$n'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sub-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sub-name')), 'Spotify');
    await tester.enterText(find.byKey(const Key('sub-price')), '119');
    await tester.enterText(find.byKey(const Key('sub-renews')), '23/01/2026');
    await tester.tap(find.byKey(const Key('sub-trial')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sub-save')));
    await tester.pumpAndSettle();
    final Subscription sp = s.all.single;
    expect(sp.trial, isTrue);
    expect(find.text('₹1,428 a year'), findsOneWidget);
    expect(find.text('Trial ends in 3 days · 23 Jan 2026'), findsOneWidget);

    expect(tester.getSize(find.byKey(Key('sub-renew-${sp.id}'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(Key('sub-renew-${sp.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Renews in 34 days · 23 Feb 2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared.last, contains('Total ₹1,428 a year'));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Trial ends in 3 days · 23 Jan 2026'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
