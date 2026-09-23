import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/category_icons.dart';
import '../../data/database.dart';
import 'categories_repository.dart';

/// Opens the category form.
/// - New top-level category: pass [kind].
/// - New subcategory: pass [kind] and [parent].
/// - Edit: pass [existing] (and [parent] if it is a subcategory).
/// Returns the category's id when saved.
Future<String?> showCategorySheet(
  BuildContext context, {
  required CategoryKind kind,
  CategoryItem? parent,
  CategoryItem? existing,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => CategorySheet(kind: kind, parent: parent, existing: existing),
  );
}

class CategorySheet extends ConsumerStatefulWidget {
  const CategorySheet({
    super.key,
    required this.kind,
    this.parent,
    this.existing,
  });

  final CategoryKind kind;
  final CategoryItem? parent;
  final CategoryItem? existing;

  @override
  ConsumerState<CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<CategorySheet> {
  final _name = TextEditingController();
  late String _iconKey;
  late BudgetTag _tag;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;
  bool get _isSub => widget.parent != null;

  /// Only top-level expense categories choose Needs or Wants;
  /// subcategories follow their parent.
  bool get _showTag => widget.kind == CategoryKind.expense && !_isSub;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name.text = e?.name ?? '';
    _iconKey = e?.iconKey ??
        widget.parent?.iconKey ??
        (widget.kind == CategoryKind.income ? 'work' : 'more_horiz');
    _tag = e?.budgetTag ?? widget.parent?.budgetTag ?? BudgetTag.essentials;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSave => !_saving && _name.text.trim().isNotEmpty;

  String get _title {
    final what = _isSub ? 'subcategory' : 'category';
    if (_isEditing) return 'Edit $what';
    if (_isSub) return 'New subcategory in ${widget.parent!.name}';
    return widget.kind == CategoryKind.income
        ? 'New income category'
        : 'New expense category';
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final repo = ref.read(categoriesRepositoryProvider);
    final navigator = Navigator.of(context);
    final name = _name.text.trim();

    final existing = widget.existing;
    if (existing != null) {
      await repo.update(
        existing.copyWith(
          name: name,
          iconKey: _iconKey,
          budgetTag: _showTag ? Value(_tag) : Value(existing.budgetTag),
        ),
      );
      navigator.pop(existing.id);
    } else {
      final id = await repo.add(
        name: name,
        kind: widget.kind,
        iconKey: _iconKey,
        budgetTag: widget.kind == CategoryKind.expense ? _tag : null,
        parentId: widget.parent?.id,
      );
      navigator.pop(id);
    }
  }

  Future<void> _remove() async {
    final c = widget.existing!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${c.name}?'),
        content: Text(
          _isSub
              ? 'It will no longer appear when adding transactions. Past '
                  'entries keep it, so your history stays correct.'
              : 'It and its subcategories will no longer appear when adding '
                  'transactions. Past entries keep them, so your history '
                  'stays correct.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.buoyRed),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    await ref.read(categoriesRepositoryProvider).remove(c.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _title,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: _isSub
                    ? 'e.g. Electricity'
                    : widget.kind == CategoryKind.income
                        ? 'e.g. Rental income'
                        : 'e.g. Childcare',
                filled: true,
                fillColor: AppColors.foam,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_showTag) ...[
              const SizedBox(height: 16),
              Text(
                'Is this a need or a want?',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              SegmentedButton<BudgetTag>(
                segments: const [
                  ButtonSegment(value: BudgetTag.essentials, label: Text('Need')),
                  ButtonSegment(value: BudgetTag.wants, label: Text('Want')),
                ],
                selected: {_tag},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _tag = s.first),
              ),
              const SizedBox(height: 6),
              Text(
                _tag == BudgetTag.essentials
                    ? 'Needs are costs you must pay to live and work.'
                    : 'Wants make life enjoyable but could be paused if needed.',
                style: text.bodySmall?.copyWith(color: AppColors.mist),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Icon',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final key in categoryIconKeys)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _iconKey = key),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor:
                          key == _iconKey ? AppColors.tide : AppColors.shallows,
                      child: Icon(
                        iconFor(key),
                        size: 20,
                        color: key == _iconKey
                            ? Colors.white
                            : AppColors.deepWater,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _canSave ? _save : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(_isEditing ? 'Save changes' : 'Create'),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving ? null : _remove,
                style: TextButton.styleFrom(foregroundColor: AppColors.buoyRed),
                icon: const Icon(Icons.remove_circle_outline_rounded),
                label: const Text('Remove'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
