import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/records/loans.dart';
import 'package:family_utility_app/records/loans/loans_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

class RecordingReminders implements LoanReminderScheduler {
  List<LoanReminder> last = <LoanReminder>[];
  @override
  Future<void> replaceAll(List<LoanReminder> reminders) async => last = reminders;
}

Loans make({LoanReminderScheduler? reminders}) => Loans(
      space: newSpace(),
      soloStore: FamilyStore(deviceId: 'me'),
      reminders: reminders ?? const NoLoanReminders(),
      now: () => DateTime(2026, 3, 20, 10),
    );

void main() {
  group('engine', () {
    test('EMI, amortisation schedule, balance, prepayment what-if, reminders, undo', () async {
      expect(Loans.emiFor(100000000, 9, 120), 1266758);
      expect(Loans.emiFor(1200000, 0, 12), 100000);

      final RecordingReminders rec = RecordingReminders();
      final Loans s = make(reminders: rec);
      expect(s.add(name: 'Bad', principal: 0, ratePct: 9, months: 12, firstEmi: DateTime(2026, 1, 5)), isNull);
      final Loan home = s.add(name: 'Home loan', principal: 100000000, ratePct: 9, months: 120, firstEmi: DateTime(2026, 1, 5))!;

      final List<EmiRow> rows = Loans.schedule(home);
      expect(rows.length, 120);
      expect((rows.first.interest, rows.first.principal, rows.first.balance), (750000, 516758, 99483242));
      expect(rows.last.on, DateTime(2035, 12, 5));
      expect(rows.last.balance, 0);
      expect(Loans.totalInterest(rows), 52010910);
      expect(s.balanceToday(home), 98438070);
      expect(s.nextEmi(home)!.on, DateTime(2026, 4, 5));

      final PrepaymentEffect e = Loans.whatIf(home, 20000000, DateTime(2026, 6, 1));
      expect(e.monthsSaved, 32);
      expect(e.interestSaved, 21801648);
      expect(e.newLastEmi, DateTime(2033, 4, 5));
      expect(e.oldLastEmi, DateTime(2035, 12, 5));

      await Future<void>.delayed(Duration.zero);
      expect(rec.last.map((LoanReminder r) => (r.title, r.at)).toList(), <(String, DateTime)>[
        ('Home loan EMI in 2 days', DateTime(2026, 4, 3, 9)),
        ('Home loan EMI is due today', DateTime(2026, 4, 5, 9)),
      ]);
      expect(rec.last.first.body, startsWith('₹12,667.58 on 5 Apr 2026'));

      expect(s.prepay(home.id, 20000000, on: DateTime(2026, 3, 20)), isTrue);
      expect(s.balanceToday(s.byId(home.id)!), 78438070);
      expect(s.undo(), isTrue);
      expect(s.balanceToday(s.byId(home.id)!), 98438070);
      expect(Loans.scheduleCsv(home).split('\r\n')[1], '1,2026-01-05,12667.58,7500.00,5167.58,994832.42');
    });

    test('shared with the family', () async {
      final FamilySpace a = newSpace();
      await a.create(familyName: 'Shahs', memberName: 'Asha');
      Loans(space: a, now: () => DateTime(2026, 3, 20)).add(name: 'Car', principal: 50000000, ratePct: 8.5, months: 60, firstEmi: DateTime(2026, 2, 10));
      final FamilySpace b = newSpace();
      await b.create(familyName: 'x', memberName: 'Ravi');
      b.store.mergeAll(a.store.allRecords);
      expect(Loans(space: b, now: () => DateTime(2026, 3, 20)).all.single.ratePct, 8.5);
    });
  });

  testWidgets('screen: add loan, schedule, what-if, record prepayment, share CSV, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final Loans s = make();
    final List<String> shared = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: LoansScreen(loans: s, share: (String t) async => shared.add(t), save: (String t, String n) async => '/x/$n'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('loan-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('loan-name')), 'Home loan');
    await tester.enterText(find.byKey(const Key('loan-amount')), '10,00,000');
    await tester.enterText(find.byKey(const Key('loan-rate')), '9');
    await tester.enterText(find.byKey(const Key('loan-months')), '120');
    await tester.enterText(find.byKey(const Key('loan-first')), '05/01/2026');
    await tester.tap(find.byKey(const Key('loan-save')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('loan-emi'))).data, 'EMI ₹12,667.58');
    expect(find.text('Balance today ₹984,380.70'), findsOneWidget);
    expect(find.text('Next EMI 5 Apr 2026'), findsOneWidget);
    expect(find.byKey(const Key('loan-row-1')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('loan-extra')), '200000');
    expect(tester.getSize(find.byKey(const Key('loan-whatif'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('loan-whatif')));
    await tester.pumpAndSettle();
    expect(find.text('Saves 33 EMIs and ₹223,573.62 interest; last EMI Mar 2033 instead of Dec 2035'), findsOneWidget);

    await tester.tap(find.byKey(const Key('loan-prepay')));
    await tester.pumpAndSettle();
    expect(find.text('Balance today ₹784,380.70'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared.last, startsWith('No,Date,EMI,Interest,Principal,Balance'));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Balance today ₹984,380.70'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
