import 'package:drift/drift.dart';

import 'database.dart';

/// Runs [load] now, then again whenever any of [tables] changes.
/// Handy for screens whose numbers come from several tables at once.
Stream<T> watchTables<T>(
  AppDatabase db,
  List<TableInfo> tables,
  Future<T> Function() load,
) async* {
  yield await load();
  await for (final _ in db.tableUpdates(TableUpdateQuery.onAllTables(tables))) {
    yield await load();
  }
}
