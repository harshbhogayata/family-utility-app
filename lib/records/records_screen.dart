import 'package:flutter/material.dart';

import 'expenses/expense_screen.dart';
import 'medicines/medicine_screen.dart';

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Records', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Money, health, documents and home records, kept on this phone.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 16),
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
          ],
        ),
      ),
    );
  }
}
