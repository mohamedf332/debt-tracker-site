import 'package:sqflite_common/sqlite_api.dart';
import '../models/transaction_attachment.dart';
import 'db_helper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final attachmentDaoProvider = Provider<AttachmentDao>((ref) {
  return AttachmentDao();
});

class AttachmentDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  Future<int> insertAttachment(TransactionAttachment attachment) async {
    final db = await _db;
    return db.insert('transaction_attachments', attachment.toMapForInsert());
  }

  Future<int> deleteAttachment(int id) async {
    final db = await _db;
    return db.delete(
      'transaction_attachments',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAttachmentsForTransaction(int transactionId) async {
    final db = await _db;
    return db.delete(
      'transaction_attachments',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
    );
  }

  Future<TransactionAttachment?> getAttachment(int id) async {
    final db = await _db;
    final maps = await db.query(
      'transaction_attachments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TransactionAttachment.fromMap(maps.first);
  }

  Future<List<TransactionAttachment>> getAttachmentsForTransaction(
    int transactionId,
  ) async {
    final db = await _db;
    final maps = await db.query(
      'transaction_attachments',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      orderBy: 'created_at ASC',
    );
    return maps.map((map) => TransactionAttachment.fromMap(map)).toList();
  }
}
