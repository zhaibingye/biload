import 'dart:convert';

import 'package:background_downloader/background_downloader.dart' hide Database;
import 'package:sqlite3/sqlite3.dart';

/// Download state stays beside the application database.
class TransferStore implements PersistentStorage {
  TransferStore(String path) : db = sqlite3.open(path) {
    db.execute(
      'CREATE TABLE IF NOT EXISTS transfers (kind TEXT, id TEXT, data TEXT NOT NULL, PRIMARY KEY(kind,id))',
    );
  }
  final Database db;
  void put(String kind, String id, Map<String, dynamic> data) => db.execute(
    'INSERT OR REPLACE INTO transfers VALUES (?,?,?)',
    [kind, id, jsonEncode(data)],
  );
  Map<String, dynamic>? get(String kind, String id) {
    final rows = db.select('SELECT data FROM transfers WHERE kind=? AND id=?', [
      kind,
      id,
    ]);
    return rows.isEmpty
        ? null
        : jsonDecode(rows.single['data'] as String) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> all(String kind) => [
    for (final row in db.select('SELECT data FROM transfers WHERE kind=?', [
      kind,
    ]))
      jsonDecode(row['data'] as String) as Map<String, dynamic>,
  ];
  void remove(String kind, String? id) {
    if (id == null) {
      db.execute('DELETE FROM transfers WHERE kind=?', [kind]);
    } else {
      db.execute('DELETE FROM transfers WHERE kind=? AND id=?', [kind, id]);
    }
  }

  @override
  (String, int) get currentDatabaseVersion => ('biload-transfers', 1);
  @override
  Future<(String, int)> get storedDatabaseVersion async =>
      currentDatabaseVersion;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> storeTaskRecord(TaskRecord record) async =>
      put('record', record.taskId, record.toJson());
  @override
  Future<TaskRecord?> retrieveTaskRecord(String taskId) async {
    final value = get('record', taskId);
    return value == null ? null : TaskRecord.fromJson(value);
  }

  @override
  Future<List<TaskRecord>> retrieveAllTaskRecords() async =>
      all('record').map(TaskRecord.fromJson).toList();
  @override
  Future<void> removeTaskRecord(String? taskId) async =>
      remove('record', taskId);
  @override
  Future<void> storePausedTask(Task task) async =>
      put('paused', task.taskId, task.toJson());
  @override
  Future<Task?> retrievePausedTask(String taskId) async {
    final value = get('paused', taskId);
    return value == null ? null : Task.createFromJson(value);
  }

  @override
  Future<List<Task>> retrieveAllPausedTasks() async =>
      all('paused').map(Task.createFromJson).toList();
  @override
  Future<void> removePausedTask(String? taskId) async =>
      remove('paused', taskId);
  @override
  Future<void> storeResumeData(ResumeData data) async =>
      put('resume', data.task.taskId, data.toJson());
  @override
  Future<ResumeData?> retrieveResumeData(String taskId) async {
    final value = get('resume', taskId);
    return value == null ? null : ResumeData.fromJson(value);
  }

  @override
  Future<List<ResumeData>> retrieveAllResumeData() async =>
      all('resume').map(ResumeData.fromJson).toList();
  @override
  Future<void> removeResumeData(String? taskId) async =>
      remove('resume', taskId);
}
