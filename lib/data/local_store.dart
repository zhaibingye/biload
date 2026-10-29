import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../core/models.dart';

class LocalStore {
  LocalStore(String path) : db = sqlite3.open(path) {
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA busy_timeout=5000');
    db.execute(
      'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS jobs (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS resources (id TEXT PRIMARY KEY, job_id TEXT NOT NULL, data TEXT NOT NULL)',
    );
    db.execute('CREATE INDEX IF NOT EXISTS resources_job ON resources(job_id)');
    db.execute('PRAGMA user_version=1');
  }
  final Database db;
  String? setting(String key) {
    final rows = db.select('SELECT value FROM settings WHERE key=?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setSetting(String key, String value) => db.execute(
    'INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );
  List<DownloadJob> loadJobs() =>
      db
          .select('SELECT data FROM jobs')
          .map(
            (row) =>
                DownloadJob.fromJson(object(jsonDecode(row['data'] as String))),
          )
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  void saveJob(DownloadJob job) => db.execute(
    'INSERT INTO jobs(id,data) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
    [job.id, jsonEncode(job.toJson())],
  );
  void removeJob(String id) {
    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM resources WHERE job_id=?', [id]);
      db.execute('DELETE FROM jobs WHERE id=?', [id]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Json? resource(String id) {
    final rows = db.select('SELECT data FROM resources WHERE id=?', [id]);
    return rows.isEmpty
        ? null
        : object(jsonDecode(rows.first['data'] as String));
  }

  void saveResource(String id, String job, Json data) => db.execute(
    'INSERT INTO resources(id,job_id,data) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
    [id, job, jsonEncode(data)],
  );
  void close() => db.close();
}
