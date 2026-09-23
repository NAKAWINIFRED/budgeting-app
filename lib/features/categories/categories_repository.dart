import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/lookups.dart';

/// A top-level category with its subcategories.
class CategoryNode {
  CategoryNode(this.category, this.children);

  final CategoryItem category;
  final List<CategoryItem> children;
}

/// Active categories of one kind, arranged as parents with children.
final categoryTreeProvider =
    Provider.family<AsyncValue<List<CategoryNode>>, CategoryKind>((ref, kind) {
  return ref.watch(categoriesProvider(kind)).whenData(buildCategoryTree);
});

List<CategoryNode> buildCategoryTree(List<CategoryItem> all) {
  final parents = all.where((c) => c.parentId == null).toList();
  return [
    for (final p in parents)
      CategoryNode(p, all.where((c) => c.parentId == p.id).toList()),
  ];
}

class CategoriesRepository {
  CategoriesRepository(this._db);

  final AppDatabase _db;

  Future<String> add({
    required String name,
    required CategoryKind kind,
    required String iconKey,
    BudgetTag? budgetTag,
    String? parentId,
  }) async {
    final id = const Uuid().v4();
    // New categories go to the end of their list.
    final siblings = await (_db.select(_db.categories)
          ..where(
            (c) =>
                c.kind.equalsValue(kind) &
                (parentId == null
                    ? c.parentId.isNull()
                    : c.parentId.equals(parentId)),
          ))
        .get();
    final nextOrder = siblings.fold<int>(
          -1,
          (max, c) => c.sortOrder > max ? c.sortOrder : max,
        ) +
        1;

    await _db.into(_db.categories).insert(
          CategoriesCompanion.insert(
            id: Value(id),
            name: name,
            kind: kind,
            iconKey: iconKey,
            budgetTag: Value(kind == CategoryKind.expense ? budgetTag : null),
            parentId: Value(parentId),
            sortOrder: Value(nextOrder),
          ),
        );
    return id;
  }

  /// Saves changes. If a parent's budget tag changes, its subcategories
  /// follow so the plan keeps counting them in the same bucket.
  Future<void> update(CategoryItem category) => _db.transaction(() async {
        await _db
            .update(_db.categories)
            .replace(category.copyWith(updatedAt: DateTime.now()));
        if (category.parentId == null) {
          await (_db.update(_db.categories)
                ..where((c) => c.parentId.equals(category.id)))
              .write(CategoriesCompanion(budgetTag: Value(category.budgetTag)));
        }
      });

  /// Hides a category (and its subcategories) from new entries. Past
  /// transactions keep it, so history and totals stay correct.
  Future<void> remove(String id) => _db.transaction(() async {
        const archived = CategoriesCompanion(isArchived: Value(true));
        await (_db.update(_db.categories)..where((c) => c.id.equals(id)))
            .write(archived);
        await (_db.update(_db.categories)..where((c) => c.parentId.equals(id)))
            .write(archived);
      });
}

final categoriesRepositoryProvider = Provider<CategoriesRepository>(
  (ref) => CategoriesRepository(ref.watch(appDatabaseProvider)),
);
