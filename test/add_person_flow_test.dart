import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debt_tracker/db/db_helper.dart';
import 'package:debt_tracker/db/payment_dao.dart';
import 'package:debt_tracker/db/person_dao.dart';
import 'package:debt_tracker/db/transaction_dao.dart';
import 'package:debt_tracker/models/person.dart';
import 'package:debt_tracker/models/transaction.dart';
import 'package:debt_tracker/providers/persons_provider.dart';
import 'package:debt_tracker/screens/add_person_screen.dart';
import 'package:debt_tracker/services/export_service.dart';

/// The "أول معاملة" section has to produce a real row, so these tests run
/// against the real schema: the person and the transaction are written
/// through the very code path the screen calls, then read back with the same
/// DAOs the home list, the balance cards and the person detail screen use.
void main() {
  Directory? tempDir;

  String dbPath() => p.join(tempDir!.path, 'debt_tracker.db');

  setUpAll(() => initializeDateFormatting('ar_EG'));

  setUp(() async {
    await DatabaseHelper.instance.close();
    if (tempDir != null && tempDir!.existsSync()) {
      tempDir!.deleteSync(recursive: true);
    }
    tempDir = Directory.systemTemp.createTempSync('debt_tracker_add_person');
    DatabaseHelper.databasePathOverride = dbPath();
    // The notifier arms a debounced Drive backup on every change; the mode is
    // off by default, which is all it needs to return immediately.
    SharedPreferences.setMockInitialValues({});
    // Open the database and warm SharedPreferences while real async still
    // runs, so no open/migration ever happens inside the fake test zone.
    await DatabaseHelper.instance.database;
    await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    DatabaseHelper.databasePathOverride = null;
    if (tempDir != null && tempDir!.existsSync()) {
      tempDir!.deleteSync(recursive: true);
    }
    tempDir = null;
  });

  Person person([String name = 'أحمد']) =>
      Person(name: name, createdAt: '', updatedAt: '');

  Transaction initial(
    int personId, {
    double amount = 250,
    TransactionType type = TransactionType.theyOweMe,
    bool settled = false,
    String date = '2026-01-05T10:00:00.000',
    String? note = 'دفعة أولى',
  }) => Transaction(
    personId: personId,
    projectId: null,
    amount: amount,
    type: type,
    note: note,
    date: date,
    createdAt: date,
    isSettled: settled,
    settledAt: settled ? DateTime.parse(date) : null,
  );

  Future<ProviderContainer> container() async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('initial transaction', () {
    test('is a real row with no project and refreshes the home totals',
        () async {
      final c = await container();

      final before = await c.read(overallTotalsProvider.future);
      expect(before['they_owe_me'], 0);

      await c.read(personsProvider.notifier).addPerson(
            person(),
            initialTransaction: (personId) => initial(personId),
          );

      final persons = c.read(personsProvider).persons;
      expect(persons, hasLength(1));
      expect(persons.first.id, isNotNull);
      final personId = persons.first.id!;

      final rows = await TransactionDao().getAllTransactionsForPerson(personId);
      expect(rows, hasLength(1));
      expect(rows.first.projectId, isNull, reason: 'lands on the الكل tab');
      expect(rows.first.amount, 250);
      expect(rows.first.type, TransactionType.theyOweMe);
      expect(rows.first.note, 'دفعة أولى');
      expect(rows.first.isSettled, isFalse);
      expect(
        await PaymentDao().getPaymentsForTransaction(rows.first.id!),
        isEmpty,
        reason: 'an unsettled row has no payment history',
      );

      expect(await PersonDao().getPersonBalance(personId), 250);
      expect(await PersonDao().getPersonTotals(personId), {
        'they_owe_me': 250.0,
        'i_owe_them': 0.0,
      });

      final after = await c.read(overallTotalsProvider.future);
      expect(after['they_owe_me'], 250, reason: 'home totals refresh now');
    });

    test('born settled gets one full payment and leaves the unsettled totals',
        () async {
      final c = await container();

      await c.read(personsProvider.notifier).addPerson(
            person(),
            initialTransaction: (personId) => initial(
              personId,
              amount: 300,
              type: TransactionType.iOweThem,
              settled: true,
            ),
          );

      final personId = c.read(personsProvider).persons.first.id!;
      final rows = await TransactionDao().getAllTransactionsForPerson(personId);
      expect(rows, hasLength(1));

      final payments = await PaymentDao().getPaymentsForTransaction(
        rows.first.id!,
      );
      expect(payments, hasLength(1), reason: 'exactly one full payment');
      expect(payments.first.amount, 300);
      expect(payments.first.date, rows.first.date);

      final reloaded = (await TransactionDao().getTransaction(rows.first.id!))!;
      expect(reloaded.isSettled, isTrue, reason: 'derived from the payment');

      // Unsettled view excludes it entirely…
      expect(await PersonDao().getPersonBalance(personId), 0);
      expect(await PersonDao().getPersonTotals(personId), {
        'they_owe_me': 0.0,
        'i_owe_them': 0.0,
      });
      // …while the settled view carries the signed amount.
      expect(await PersonDao().getPersonSettledTotal(personId), -300);
    });

    test('both directions keep their sign', () async {
      final c = await container();
      final notifier = c.read(personsProvider.notifier);

      await notifier.addPerson(
        person('سامي'),
        initialTransaction: (personId) => initial(
          personId,
          amount: 100,
          type: TransactionType.theyOweMe,
          settled: true,
        ),
      );
      await notifier.addPerson(
        person('نور'),
        initialTransaction: (personId) => initial(
          personId,
          amount: 40,
          type: TransactionType.iOweThem,
        ),
      );

      final byName = {
        for (final p in c.read(personsProvider).persons) p.name: p.id!,
      };

      expect(await PersonDao().getPersonSettledTotal(byName['سامي']!), 100);
      expect(await PersonDao().getPersonBalance(byName['نور']!), -40);

      final totals = await PersonDao().getPersonTotals(byName['نور']!);
      expect(totals['i_owe_them'], 40);

      final overall = await c.read(overallTotalsProvider.future);
      expect(overall['they_owe_me'], 0, reason: 'the settled row is excluded');
      expect(overall['i_owe_them'], 40);
      expect(overall['net'], -40);
    });

    test('a failing transaction insert rolls the person back', () async {
      final c = await container();
      final notifier = c.read(personsProvider.notifier);

      await expectLater(
        notifier.addPerson(
          person(),
          // Rejected by the creator *inside* the db transaction.
          initialTransaction: (personId) => initial(personId, amount: 0),
        ),
        throwsA(isA<PaymentValidationException>()),
      );

      expect(await PersonDao().getActivePersons(), isEmpty);
      expect(
        await PersonDao().getAllPersons(includeArchived: true),
        isEmpty,
        reason: 'no half-saved person is left behind',
      );
      expect(c.read(personsProvider).persons, isEmpty);
      expect(await TransactionDao().getAllTransactionsForPerson(1), isEmpty);
    });

    test('the backup carries the row and its payment like any other one',
        () async {
      final c = await container();

      await c.read(personsProvider.notifier).addPerson(
            person(),
            initialTransaction: (personId) => initial(
              personId,
              amount: 300,
              settled: true,
            ),
          );

      final data = await ExportService.instance.buildFullExportData();
      final exported =
          (data['persons'] as List).single as Map<String, dynamic>;

      final rows = exported['transactions_without_project'] as List;
      expect(rows, hasLength(1));

      final row = rows.single as Map<String, dynamic>;
      expect(row['amount'], 300);
      expect(row['type'], 'they_owe_me');
      expect(row['is_settled'], 1);

      final payments = row['payments'] as List;
      expect(payments, hasLength(1));
      expect(payments.single['amount'], 300);
    });
  });

  group('add person form', () {
    /// Room for the whole form, so every field and the save button are on
    /// screen without scrolling.
    void tallSurface(WidgetTester tester) {
      final size = tester.view.physicalSize;
      final dpr = tester.view.devicePixelRatio;
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = dpr;
      });
    }

    /// The screen is pushed onto a launcher so saving has a route to pop to.
    Future<void> openForm(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: _Launcher())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('شاشة الإضافة'));
      await tester.pumpAndSettle();
      expect(find.byType(AddPersonScreen), findsOneWidget);
    }

    Finder nameField() => find.byType(TextFormField).at(0);
    Finder amountField() => find.byType(TextFormField).at(1);

    /// Taps save and gives the real database work real-async windows until
    /// the save future resolves (the loading spinner disappears), because a
    /// test body never processes real events on its own.
    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.text('حفظ'));
      await tester.pump();
      await tester.tap(find.text('حفظ'));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      // Fake time has to move for the pop transition to finish; a bare pump()
      // advances zero frames of the route animation.
      await tester.pump(const Duration(seconds: 1));
    }

    /// Clears the debounced backup timer every write arms.
    Future<void> drainBackupTimer(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 31));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
    }

    testWidgets('rejects a missing name and a bad amount before saving',
        (tester) async {
      tallSurface(tester);
      await openForm(tester);

      await save(tester);
      expect(find.text('الاسم مطلوب'), findsOneWidget);

      await tester.enterText(nameField(), 'أحمد');
      await tester.enterText(amountField(), 'abc');
      await save(tester);
      expect(find.text('أدخل مبلغ أكبر من صفر'), findsOneWidget);

      await tester.enterText(amountField(), '-5');
      await save(tester);
      expect(find.text('أدخل مبلغ أكبر من صفر'), findsOneWidget);

      final left =
          (await tester.runAsync(() => PersonDao().getActivePersons()))!;
      expect(left, isEmpty);
      expect(find.byType(AddPersonScreen), findsOneWidget,
          reason: 'still on the form: nothing was saved');

      await drainBackupTimer(tester);
    });

    testWidgets('an empty amount saves the person and no transaction',
        (tester) async {
      tallSurface(tester);
      await openForm(tester);
      await tester.enterText(nameField(), 'أحمد');
      await save(tester);

      final persons =
          (await tester.runAsync(() => PersonDao().getActivePersons()))!;
      expect(persons, hasLength(1));
      final rows = (await tester.runAsync(
        () => TransactionDao().getAllTransactionsForPerson(persons.first.id!),
      ))!;
      expect(rows, isEmpty);
      expect(find.byType(AddPersonScreen), findsNothing,
          reason: 'the form was popped after saving');

      await drainBackupTimer(tester);
    });

    testWidgets('the settled switch follows the type and saves a paid row',
        (tester) async {
      tallSurface(tester);
      await openForm(tester);

      // Default direction is money coming in, so the switch reads "received".
      expect(find.text('تم الاستلام؟'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.text('عليّا'));
      await tester.pump();
      expect(find.text('تم الدفع؟'), findsOneWidget,
          reason: 'the label follows the type immediately');
      expect(find.text('تم الاستلام؟'), findsNothing);

      await tester.tap(find.text('ليا عنده'));
      await tester.pump();
      expect(find.text('تم الاستلام؟'), findsOneWidget);

      await tester.enterText(nameField(), 'أحمد');
      await tester.enterText(amountField(), '150');
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await save(tester);

      final persons =
          (await tester.runAsync(() => PersonDao().getActivePersons()))!;
      expect(persons, hasLength(1));
      final rows = (await tester.runAsync(
        () => TransactionDao().getAllTransactionsForPerson(persons.first.id!),
      ))!;
      expect(rows, hasLength(1));
      expect(rows.first.amount, 150);
      expect(rows.first.isSettled, isTrue);
      expect(rows.first.projectId, isNull);

      final payments = (await tester.runAsync(
        () => PaymentDao().getPaymentsForTransaction(rows.first.id!),
      ))!;
      expect(payments, hasLength(1));
      expect(payments.first.amount, 150);
      expect(payments.first.date, rows.first.date);

      final balance = (await tester.runAsync(
        () => PersonDao().getPersonBalance(persons.first.id!),
      ))!;
      expect(balance, 0,
          reason: 'a settled row is out of the unsettled balance');
      final settledTotal = (await tester.runAsync(
        () => PersonDao().getPersonSettledTotal(persons.first.id!),
      ))!;
      expect(settledTotal, 150);

      await drainBackupTimer(tester);
    });
  });
}

class _Launcher extends StatelessWidget {
  const _Launcher();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const AddPersonScreen()),
            );
          },
          child: const Text('شاشة الإضافة'),
        ),
      ),
    );
  }
}
