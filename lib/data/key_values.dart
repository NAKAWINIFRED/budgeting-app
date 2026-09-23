import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';
import 'database_provider.dart';

/// Tiny settings store: read and write text values by key.
class KeyValueStore {
  KeyValueStore(this._db);

  final AppDatabase _db;

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.keyValues)..where((k) => k.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) => _db
      .into(_db.keyValues)
      .insertOnConflictUpdate(KeyValuesCompanion.insert(key: key, value: value));

  Stream<String?> watch(String key) =>
      (_db.select(_db.keyValues)..where((k) => k.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);
}

final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => KeyValueStore(ref.watch(appDatabaseProvider)),
);
