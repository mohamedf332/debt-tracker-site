import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _database;
  static DatabaseFactory? _factory;

  /// Lets tests point the app schema at a temp file instead of the documents
  /// directory (which needs path_provider, i.e. a real platform channel).
  @visibleForTesting
  static String? databasePathOverride;

  static Future<void> initialize() async {
    if (_factory != null) return;

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      _factory = databaseFactoryFfi;
    } else {
      _factory = databaseFactory;
    }
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    await initialize();
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final factory = _factory;
    if (factory == null) {
      throw StateError('DatabaseFactory was not initialized.');
    }

    final dbPath = await _resolvePath();

    return factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 5,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            // Add missing columns to persons table
            await db.execute('ALTER TABLE persons ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0');
            await db.execute('ALTER TABLE persons ADD COLUMN pin_order INTEGER NULL');
            await db.execute('ALTER TABLE persons ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0');
            
            // Add missing date column to transactions table (old schema used transaction_datetime)
            final transactionColumns = await db.rawQuery("PRAGMA table_info(transactions)");
            final hasDateColumn = transactionColumns.any((col) => col['name'] == 'date');
            if (!hasDateColumn) {
              // Check if transaction_datetime exists and rename it, or add date column
              final hasTransactionDateTime = transactionColumns.any((col) => col['name'] == 'transaction_datetime');
              if (hasTransactionDateTime) {
                await db.execute('ALTER TABLE transactions RENAME COLUMN transaction_datetime TO date');
              } else {
                await db.execute('ALTER TABLE transactions ADD COLUMN date TEXT NOT NULL DEFAULT (datetime(\'now\'))');
              }
            }
            
            // Check if projects table exists before trying to alter it
            final projectsTableExists = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='projects'"
            );
            if (projectsTableExists.isNotEmpty) {
              await db.execute('ALTER TABLE projects ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0');
            } else {
              // Create projects table if it doesn't exist
              await db.execute('''
                CREATE TABLE projects (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  person_id INTEGER NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
                  name TEXT NOT NULL,
                  budget REAL NULL,
                  is_archived INTEGER NOT NULL DEFAULT 0,
                  created_at TEXT NOT NULL,
                  updated_at TEXT NOT NULL
                )
              ''');
              await db.execute('CREATE INDEX idx_projects_person_id ON projects(person_id)');
            }
          }
          if (oldVersion < 3) {
            // Remove counts_to_budget and is_budget_expense columns from transactions table
            // SQLite doesn't support DROP COLUMN directly, so we recreate the table
            await db.execute('''
              CREATE TABLE transactions_new (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                person_id INTEGER NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
                project_id INTEGER NULL REFERENCES projects(id) ON DELETE SET NULL,
                amount REAL NOT NULL CHECK (amount > 0),
                type TEXT NOT NULL CHECK (type IN ('they_owe_me', 'i_owe_them')),
                note TEXT NULL,
                date TEXT NOT NULL,
                created_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              INSERT INTO transactions_new (id, person_id, project_id, amount, type, note, date, created_at)
              SELECT id, person_id, project_id, amount, type, note, date, created_at
              FROM transactions
            ''');
            await db.execute('DROP TABLE transactions');
            await db.execute('ALTER TABLE transactions_new RENAME TO transactions');
            await db.execute('CREATE INDEX idx_transactions_person_id ON transactions(person_id)');
            await db.execute('CREATE INDEX idx_transactions_project_id ON transactions(project_id)');
            await db.execute('CREATE INDEX idx_transactions_date ON transactions(date)');
          }
          if (oldVersion < 4) {
            // Settlement status (4-state model). Existing rows stay unsettled.
            await db.execute(
                'ALTER TABLE transactions ADD COLUMN is_settled INTEGER NOT NULL DEFAULT 0');
            await db.execute('ALTER TABLE transactions ADD COLUMN settled_at TEXT NULL');
          }
          if (oldVersion < 5) {
            // Payment history becomes the single source of truth for status.
            await _createPaymentTables(db);
            await _backfillPaymentsFromSettled(db);
            await _dropAllowPartialIfPresent(db);
          }
        },
        onOpen: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
  }

  Future<void> _createTables(Database db) async {
    // persons table
    await db.execute('''
      CREATE TABLE persons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        pin_order INTEGER NULL,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // projects table
    await db.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        person_id INTEGER NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        budget REAL NULL,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_projects_person_id ON projects(person_id)');

    // transactions table (without counts_to_budget and is_budget_expense)
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        person_id INTEGER NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
        project_id INTEGER NULL REFERENCES projects(id) ON DELETE SET NULL,
        amount REAL NOT NULL CHECK (amount > 0),
        type TEXT NOT NULL CHECK (type IN ('they_owe_me', 'i_owe_them')),
        note TEXT NULL,
        date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_settled INTEGER NOT NULL DEFAULT 0,
        settled_at TEXT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_transactions_person_id ON transactions(person_id)');
    await db.execute('CREATE INDEX idx_transactions_project_id ON transactions(project_id)');
    await db.execute('CREATE INDEX idx_transactions_date ON transactions(date)');

    // transaction_attachments table
    await db.execute('''
      CREATE TABLE transaction_attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
        file_path TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_attachments_transaction_id ON transaction_attachments(transaction_id)');

    await _createPaymentTables(db);
  }

  /// Every settled row gets exactly one payment for its whole amount, so
  /// `paid = SUM(payments)` is true for data written before this migration
  /// too. The settlement date is the best available "when did this land"
  /// timestamp; rows without one fall back to the transaction's own date.
  ///
  /// Must run on an empty table only: it is called from `onUpgrade`, where
  /// the payment table has just been created.
  Future<void> _backfillPaymentsFromSettled(Database db) async {
    await db.execute('''
      INSERT INTO transaction_payments
          (transaction_id, amount, date, note, created_at)
      SELECT id, amount, COALESCE(settled_at, date), NULL, COALESCE(settled_at, date)
      FROM transactions
      WHERE is_settled = 1
    ''');
  }

  /// An earlier cut of v5 shipped a per-row opt-in flag; the payment history
  /// replaced it, so the column is dead weight. SQLite only gained
  /// `DROP COLUMN` in 3.35, hence the guard.
  Future<void> _dropAllowPartialIfPresent(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(transactions)');
    final hasColumn =
        columns.any((column) => column['name'] == 'allow_partial');
    if (!hasColumn) return;
    await db.execute('ALTER TABLE transactions DROP COLUMN allow_partial');
  }

  /// Installment history. `ON DELETE CASCADE` only fires while
  /// `PRAGMA foreign_keys = ON`, which [onConfigure] sets before any migration
  /// runs and [onOpen] re-asserts on every open.
  Future<void> _createPaymentTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transaction_payments (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id  INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
        amount          REAL NOT NULL CHECK (amount > 0),
        date            TEXT NOT NULL,
        note            TEXT NULL,
        created_at      TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_transaction_id ON transaction_payments(transaction_id)');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  /// Where the database file lives. Tests swap in a temp path so the real
  /// schema (including migrations) can be exercised without a platform channel.
  Future<String> _resolvePath() async {
    final overridePath = databasePathOverride;
    if (overridePath != null) return overridePath;

    final documentsDirectory = await getApplicationDocumentsDirectory();
    return join(documentsDirectory.path, 'debt_tracker.db');
  }

  Future<void> deleteDatabaseFile() async {
    final dbPath = await _resolvePath();
    await databaseFactory.deleteDatabase(dbPath);
    _database = null;
  }
}