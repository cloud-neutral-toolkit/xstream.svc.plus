import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../utils/global_config.dart';

class SqliteNodeStore {
  static Database? _db;

  static Future<Database> _openDb() async {
    if (_db != null) {
      return _db!;
    }

    final basePath = await GlobalApplicationConfig.getSandboxBasePath();
    final dbPath = p.join(basePath, 'app.db');
    final dbFile = File(dbPath);
    await dbFile.parent.create(recursive: true);

    final db = sqlite3.open(dbPath);
    db.execute('''
      CREATE TABLE IF NOT EXISTS vpn_nodes (
        name TEXT PRIMARY KEY,
        country_code TEXT NOT NULL,
        config_path TEXT NOT NULL,
        service_name TEXT NOT NULL,
        protocol TEXT NOT NULL,
        transport TEXT NOT NULL,
        security TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL
      );
    ''');

    _db = db;
    return db;
  }

  static Future<List<Map<String, dynamic>>> loadNodes() async {
    final db = await _openDb();
    final rs = db.select('''
      SELECT name, country_code, config_path, service_name,
             protocol, transport, security, enabled
      FROM vpn_nodes
      ORDER BY updated_at DESC, name ASC
    ''');

    return rs.map((row) {
      return <String, dynamic>{
        'name': (row['name'] as String?) ?? '',
        'countryCode': (row['country_code'] as String?) ?? '',
        'configPath': (row['config_path'] as String?) ?? '',
        'serviceName': (row['service_name'] as String?) ?? '',
        'protocol': (row['protocol'] as String?) ?? '',
        'transport': (row['transport'] as String?) ?? '',
        'security': (row['security'] as String?) ?? '',
        'enabled': ((row['enabled'] as int?) ?? 1) == 1,
      };
    }).toList();
  }

  static Future<void> replaceAll(List<Map<String, dynamic>> nodes) async {
    final db = await _openDb();
    final now = DateTime.now().millisecondsSinceEpoch;

    db.execute('BEGIN TRANSACTION');
    try {
      db.execute('DELETE FROM vpn_nodes');
      final stmt = db.prepare('''
        INSERT INTO vpn_nodes(
          name, country_code, config_path, service_name,
          protocol, transport, security, enabled, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''');
      try {
        for (final node in nodes) {
          stmt.execute([
            (node['name'] as String?) ?? '',
            (node['countryCode'] as String?) ?? '',
            (node['configPath'] as String?) ?? '',
            (node['serviceName'] as String?) ?? '',
            (node['protocol'] as String?) ?? '',
            (node['transport'] as String?) ?? '',
            (node['security'] as String?) ?? '',
            ((node['enabled'] as bool?) ?? true) ? 1 : 0,
            now,
          ]);
        }
      } finally {
        stmt.dispose();
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  static Future<void> deleteNode(String name) async {
    final db = await _openDb();
    db.execute('DELETE FROM vpn_nodes WHERE name = ?', [name]);
  }
}
