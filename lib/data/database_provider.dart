import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// One shared database for the whole app. Any screen can read it with
/// ref.watch(appDatabaseProvider).
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});