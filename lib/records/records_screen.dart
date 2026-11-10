import 'package:flutter/material.dart';

import 'bills/bills_screen.dart';
import 'doctor_visits/doctor_visits_screen.dart';
import 'elderly_care/elderly_care_screen.dart';
import 'expenses/expense_screen.dart';
import 'health_log/health_log_screen.dart';
import 'loans/loans_screen.dart';
import 'medicines/medicine_screen.dart';
import 'occasions/occasions_screen.dart';
import 'profile/autofill_profile_screen.dart';
import 'quick_add/quick_add_screen.dart';
import 'receipts/receipt_vault_screen.dart';
import 'reports/reports_vault_screen.dart';
import 'whatsapp_direct/whatsapp_direct_screen.dart';
import 'shared_expenses/shared_expenses_screen.dart';

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
