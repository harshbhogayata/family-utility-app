import 'package:flutter/material.dart';

import 'bills/bills_screen.dart';
import 'doctor_visits/doctor_visits_screen.dart';
import 'elderly_care/elderly_care_screen.dart';
import 'expenses/expense_screen.dart';
import 'health_log/health_log_screen.dart';
import 'lending/lending_screen.dart';
import 'loans/loans_screen.dart';
import 'medicines/medicine_screen.dart';
import 'occasions/occasions_screen.dart';
import 'profile/autofill_profile_screen.dart';
import 'quick_add/quick_add_screen.dart';
import 'receipts/receipt_vault_screen.dart';
import 'reports/reports_vault_screen.dart';
import 'whatsapp_direct/whatsapp_direct_screen.dart';
import 'shared_expenses/shared_expenses_screen.dart';
import 'subscriptions/subscriptions_screen.dart';
import 'warranties/warranties_screen.dart';
import 'loyalty_cards/loyalty_cards_screen.dart';
import 'where_is_it/where_is_it_screen.dart';
import 'contacts_backup/contacts_backup_screen.dart';
import 'vaccinations/vaccinations_screen.dart';
import 'health_summary/health_summary_screen.dart';

/// Records tab: quick-add, due soon, Money / Health / Documents / Home.
/// Filled in by Phase 3 features (080 onwards).
class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: <Widget>[
            Text('Records', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Money, health, documents and home records, kept on this phone.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 8),
            // 121: one line in English or Hinglish into the ledger.
            ListTile(
              key: const Key('records-quick-add'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.bolt_outlined),
              title: const Text('Quick add'),
              subtitle: const Text('Type "paid 350 milk"'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const QuickAddScreen()),
              ),
            ),
            // 096: name, DOB and saved addresses, copied in one tap.
            ListTile(
              key: const Key('records-my-details'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.badge_outlined),
              title: const Text('My details'),
              subtitle: const Text('Name, date of birth, saved addresses'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const AutofillProfileScreen()),
              ),
            ),
            // 102: message a number without saving it.
            ListTile(
              key: const Key('records-whatsapp-direct'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.chat_outlined),
              title: const Text('WhatsApp direct'),
              subtitle: const Text('Message a number without saving it'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const WhatsAppDirectScreen()),
              ),
            ),
            const SizedBox(height: 8),
            Text('Money', style: text.titleMedium),
            // 080: expenses with receipt photos, month totals and CSV.
            ListTile(
              key: const Key('records-expenses'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Expenses'),
              subtitle: const Text('Quick-add, receipts, monthly totals, CSV'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const ExpenseScreen()),
              ),
            ),
            // 081: split with family or friends, balances, settle-up.
            ListTile(
              key: const Key('records-shared-expenses'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.call_split),
              title: const Text('Shared expenses'),
              subtitle: const Text('Split bills, balances, settle-up reminders'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const SharedExpensesScreen()),
              ),
            ),
            // 083: bills with due dates, reminders, amount history and receipts.
            ListTile(
              key: const Key('records-bills'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.request_quote_outlined),
              title: const Text('Bill reminders'),
              subtitle: const Text('Electricity, water, gas, internet, rent, society dues'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const BillsScreen()),
              ),
            ),
            // 082: money lent and borrowed, due dates and reminders.
            ListTile(
              key: const Key('records-lending'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.handshake_outlined),
              title: const Text('Lending ledger'),
              subtitle: const Text('Money lent and borrowed, with reminders'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const LendingScreen()),
              ),
            ),
            // 087: loans with EMI schedule, prepayment what-if and reminders.
            ListTile(
              key: const Key('records-loans'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('Loans'),
              subtitle: const Text('EMI dates, balance, what a prepayment saves'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const LoansScreen()),
              ),
            ),
            // 084: subscriptions, trials ending and the yearly total.
            ListTile(
              key: const Key('records-subscriptions'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.subscriptions_outlined),
              title: const Text('Subscriptions'),
              subtitle: const Text('Renewals, free trials ending, cost per year'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const SubscriptionsScreen()),
              ),
            ),
            // 085: receipts searchable by shop, amount or text; expense and warranty links.
            ListTile(
              key: const Key('records-receipts'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Receipt vault'),
              subtitle: const Text('Search by shop or amount; link an expense or warranty'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const ReceiptVaultScreen()),
              ),
            ),
            // 086: warranties with the bill linked and the service number one tap away.
            ListTile(
              key: const Key('records-warranties'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.verified_outlined),
              title: const Text('Warranties'),
              subtitle: const Text('Warranty end, linked bill, service number'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const WarrantiesScreen()),
              ),
            ),
            // 099: where the spare key or the album is kept.
            ListTile(
              key: const Key('records-where'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.location_searching),
              title: const Text('Where is it?'),
              subtitle: const Text('Where things are kept, with a photo; share with the family'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const WhereIsItScreen()),
              ),
            ),
            // 100: store cards scanned once, shown at the till.
            ListTile(
              key: const Key('records-loyalty'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.loyalty_outlined),
              title: const Text('Loyalty cards'),
              subtitle: const Text('Scan once, show the barcode at the till'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const LoyaltyCardsScreen()),
              ),
            ),
            // 095: birthdays and anniversaries with gift ideas and a wish.
            ListTile(
              key: const Key('records-occasions'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.cake_outlined),
              title: const Text('Birthdays and anniversaries'),
              subtitle: const Text('Reminders a week ahead, gift ideas, wishes'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const OccasionsScreen()),
              ),
            ),
            // 103: every contact to one .vcf with photos; restore merges.
            ListTile(
              key: const Key('records-contacts-backup'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.contacts_outlined),
              title: const Text('Contacts backup'),
              subtitle: const Text('Export a .vcf with photos, restore without duplicates'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const ContactsBackupScreen()),
              ),
            ),
            const SizedBox(height: 8),
            Text('Health', style: text.titleMedium),
            // 088: dose reminders, taken / skipped log and pill stock.
            ListTile(
              key: const Key('records-medicines'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.medication_outlined),
              title: const Text('Medicines'),
              subtitle: const Text('Dose reminders, tablets left, refills'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const MedicineScreen()),
              ),
            ),
            // 092: the Indian immunisation schedule per person, with due alerts.
            ListTile(
              key: const Key('records-vaccinations'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.vaccines_outlined),
              title: const Text('Vaccinations'),
              subtitle: const Text('Child and adult schedules, due alerts, certificates'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const VaccinationsScreen()),
              ),
            ),
            // 089: BP and sugar readings, trend chart, PDF for the doctor.
            ListTile(
              key: const Key('records-health-log'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.monitor_heart_outlined),
              title: const Text('BP and sugar'),
              subtitle: const Text('Readings, trend chart, PDF for the doctor'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const HealthLogScreen()),
              ),
            ),
            // 094: one-page health summary PDF for a new doctor.
            ListTile(
              key: const Key('records-health-summary'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.summarize_outlined),
              title: const Text('Health summary'),
              subtitle: const Text('Conditions, medicines, recent readings as one PDF'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const HealthSummaryScreen()),
              ),
            ),
            // 090: doctor visits, scanned prescriptions, next appointment.
            ListTile(
              key: const Key('records-doctor-visits'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.medical_services_outlined),
              title: const Text('Doctor visits'),
              subtitle: const Text('Notes, scanned prescriptions, next appointment'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const DoctorVisitsScreen()),
              ),
            ),
            // 091: lab reports encrypted, one value charted over time.
            ListTile(
              key: const Key('records-reports'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.biotech_outlined),
              title: const Text('Lab reports'),
              subtitle: const Text('Encrypted, one value charted across reports'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const ReportsVaultScreen()),
              ),
            ),
            // 093: a care circle for a parent, shared with siblings.
            ListTile(
              key: const Key('records-elderly-care'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.elderly_outlined),
              title: const Text('Elderly care'),
              subtitle: const Text('Medicines, visits and notes, shared with siblings'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext context) => const ElderlyCareScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
