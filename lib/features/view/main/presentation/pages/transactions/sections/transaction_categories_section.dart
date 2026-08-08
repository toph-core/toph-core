import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/core/widgets/styled_virtual_keyboard.dart';
import 'package:mary_ai_pos/core/sync/sync_engine.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/settings/widgets/section_shell.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class TransactionCategoriesSection extends StatefulWidget {
  const TransactionCategoriesSection({super.key});

  @override
  State<TransactionCategoriesSection> createState() =>
      _TransactionCategoriesSectionState();
}

class _TransactionCategoriesSectionState
    extends State<TransactionCategoriesSection> {
  final MainRepository _repository = inject<MainRepository>();
  final TransactionsRepository _transactionsRepository =
      inject<TransactionsRepository>();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<_Category> _categories = const [];
  String _searchQuery = '';
  Timer? _searchDebounce;
  StreamSubscription<List<Map<String, dynamic>>>? _groupsSub;

  @override
  void initState() {
    super.initState();
    _subscribeToGroups();
  }

  @override
  void dispose() {
    _groupsSub?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// offline-first-target-architecture.md §8 Phase 5: the unfiltered default
  /// list is a reactive TransactionsRepository/LocalDatabase subscription
  /// (already hydrated by SyncEngine, §8 Phase 1); an active search query
  /// still goes straight to the network (`_load` below) — same "no bounded
  /// local mirror to search against instead" reasoning already used
  /// elsewhere in this codebase (e.g. DetailBloc's live goods search), and
  /// matches `MainRepositoryImpl.getTransactionGroups`'s own existing cache
  /// fallback, which was already scoped to the unfiltered list only.
  void _subscribeToGroups() {
    _groupsSub = _transactionsRepository.watchTransactionGroups().listen((groups) {
      if (!mounted) return;
      setState(() {
        _categories = groups.map(_Category.fromJson).toList();
        _loading = false;
        _error = null;
      });
    });
  }

  Future<void> _load() async {
    if (_searchQuery.isEmpty) return; // reactive subscription already covers this
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _repository.getTransactionGroups(search: _searchQuery);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _loading = false;
        _error = failure.getLocalizedMessage(context);
      }),
      (data) => setState(() {
        _categories = data.map(_Category.fromJson).toList();
        _loading = false;
      }),
    );
  }

  /// Re-syncs after a write. While actively searching, re-runs the search
  /// (there's no local mirror of search results); otherwise just asks for a
  /// fresh sync pass — the reactive subscription above picks it up.
  Future<void> _refreshAfterWrite() async {
    if (_searchQuery.isNotEmpty) {
      await _load();
    } else {
      await inject<SyncEngine>().tick(force: true);
    }
  }

  void _onSearchChanged(String v) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final newQuery = v.trim();
      setState(() => _searchQuery = newQuery);
      if (newQuery.isEmpty) {
        // Back to the unfiltered list — resume the reactive subscription
        // rather than a one-shot fetch.
        _groupsSub?.cancel();
        _subscribeToGroups();
      } else {
        // Stop reacting to the unfiltered list while a search is active, so
        // an unrelated background sync can't overwrite search results.
        _groupsSub?.cancel();
        _load();
      }
    });
  }

  Future<void> _openEditor({_Category? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CategoryEditDialog(repository: _repository, existing: existing),
    );
    if (saved == true && mounted) await _refreshAfterWrite();
  }

  Future<void> _confirmDelete(_Category c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(S.current.strDeleteTxnGroup),
        content: Text('${S.current.strDeleteTxnGroupConfirm}\n\n"${c.name}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.current.strCancelShort),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
            ),
            child: Text(S.current.strDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final result = await _repository.deleteTransactionGroup(c.id);
    if (!mounted) return;
    result.fold(
      (failure) => showErrorMessage(context, failure.getLocalizedMessage(context)),
      (_) => _refreshAfterWrite(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionShell(
      title: S.current.strTxnGroupsTitle,
      subtitle: _categories.isEmpty
          ? null
          : S.current.strTotalCount(_categories.length),
      trailing: SectionPrimaryButton(
        icon: Icons.add_rounded,
        label: S.current.strAddTxnGroup,
        onPressed: () => _openEditor(),
      ),
      child: Column(
        children: [
          _buildSearch(),
          const SizedBox(height: 14),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    final colors = context.colors;
    return TextField(
      controller: _searchCtrl,
      textInputAction: TextInputAction.search,
      onTap: () => AppScaffold.open(_searchCtrl, onChanged: _onSearchChanged),
      decoration: InputDecoration(
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: colors.textSecondary,
        ),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: colors.textSecondary,
                ),
                onPressed: () {
                  _searchDebounce?.cancel();
                  _searchCtrl.clear();
                  setState(() => _searchQuery = '');
                  _load();
                },
              ),
        hintText: S.current.strSearch,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onChanged: _onSearchChanged,
    );
  }

  Widget _buildBody() {
    final colors = context.colors;
    if (_loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 32, color: colors.systemError),
            const SizedBox(height: 10),
            SizedBox(
              width: 320,
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.systemError, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            SectionPrimaryButton(
              icon: Icons.refresh_rounded,
              label: S.current.strRetry,
              onPressed: _load,
            ),
          ],
        ),
      );
    }
    if (_categories.isEmpty) {
      return SectionEmptyState(
        icon: Icons.sell_outlined,
        title: S.current.strNoTxnGroupsYet,
        action: SectionPrimaryButton(
          icon: Icons.add_rounded,
          label: S.current.strAddTxnGroup,
          onPressed: () => _openEditor(),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _categories.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final c = _categories[i];
        return _CategoryCard(
          category: c,
          onEdit: () => _openEditor(existing: c),
          onDelete: () => _confirmDelete(c),
        );
      },
    );
  }
}

class _CategoryCard extends StatefulWidget {
  final _Category category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryCard({
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: colors.bgDefault,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hover ? colors.buttonBrand : colors.border,
            width: _hover ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.buttonBrand.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.sell_outlined,
                size: 20,
                color: colors.buttonBrand,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.category.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textDefault,
                ),
              ),
            ),
            IconButton(
              tooltip: S.current.strEdit,
              icon: Icon(
                Icons.edit_outlined,
                size: 20,
                color: colors.buttonBrand,
              ),
              onPressed: widget.onEdit,
            ),
            IconButton(
              tooltip: S.current.strDelete,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: colors.systemError,
              ),
              onPressed: widget.onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryEditDialog extends StatefulWidget {
  final MainRepository repository;
  final _Category? existing;

  const _CategoryEditDialog({required this.repository, this.existing});

  @override
  State<_CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends State<_CategoryEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  bool _saving = false;
  String? _error;

  bool get _isCreate => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
  }

  @override
  void dispose() {
    FloatingKeyboard.close();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final name = _nameCtrl.text.trim();
    final result = _isCreate
        ? await widget.repository.createTransactionGroup(name)
        : await widget.repository.updateTransactionGroup(widget.existing!.id, name);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _saving = false;
        _error = failure.getLocalizedMessage(context);
      }),
      (_) => Navigator.pop(context, true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.bgDefault,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isCreate
                            ? S.current.strAddTxnGroup
                            : S.current.strEditTxnGroup,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.textDefault,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close_rounded),
                      color: colors.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: true,
                  readOnly: true,
                  showCursor: true,
                  onTap: () => FloatingKeyboard.openText(context, _nameCtrl),
                  decoration: InputDecoration(
                    labelText: S.current.strTxnGroupName,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? S.current.strFieldRequired
                      : null,
                  onFieldSubmitted: (_) => _save(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: colors.systemError, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, false),
                      child: Text(S.current.strCancelShort),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.buttonBrand,
                        foregroundColor: colors.textOnBrand,
                        elevation: 0,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(S.current.strSave),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Category {
  final String id;
  final String name;

  const _Category({required this.id, required this.name});

  factory _Category.fromJson(Map<String, dynamic> json) => _Category(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
  );
}
