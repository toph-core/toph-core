import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/core/widgets/styled_virtual_keyboard.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/transactions/transaction_categories_controller.dart';
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
  final TransactionCategoriesController _controller =
      inject<TransactionCategoriesController>();
  final TextEditingController _searchCtrl = TextEditingController();

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

  /// One subscription, filtered or not.
  ///
  /// The search box used to *cancel* this subscription and swap in a one-shot
  /// query, so that "an unrelated background sync can't overwrite search
  /// results". That was a defence against a fetch, and there is no longer a
  /// fetch: both the list and the search read the same replicated catalogue,
  /// so the filter can simply be re-applied on every emission. A group renamed
  /// on another terminal now reaches this screen while a search is active,
  /// which it previously could not.
  void _subscribeToGroups() {
    _groupsSub = _controller.watchGroups().listen((groups) {
      if (!mounted) return;
      setState(() => _categories = _visible(groups));
    });
  }

  /// The rows to show: the emitted catalogue as it came, or the same
  /// catalogue narrowed by the active query.
  List<_Category> _visible(List<Map<String, dynamic>> all) {
    final rows =
        _searchQuery.isEmpty ? all : _controller.searchGroups(_searchQuery);
    return rows.map(_Category.fromJson).toList();
  }

  /// Re-runs the filter after the query itself changes. A *write* needs
  /// nothing here — the subscription re-emits when the local row lands.
  void _applyFilter() {
    if (!mounted) return;
    setState(
      () => _categories =
          _controller.searchGroups(_searchQuery).map(_Category.fromJson).toList(),
    );
  }

  void _onSearchChanged(String v) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final next = v.trim();
      if (next == _searchQuery) return;
      _searchQuery = next;
      _applyFilter();
    });
  }

  /// No refresh after save. The list is a subscription to the replica, so a
  /// write that lands locally reaches this screen the same way replication's
  /// changes do — the old forced `SyncEngine.tick` had nothing left to do, and
  /// was the last reason this widget knew the sync engine existed.
  Future<void> _openEditor({_Category? existing}) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CategoryEditDialog(controller: _controller, existing: existing),
    );
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
    // Synchronous: the row is gone from the replica and the DELETE is queued
    // before this returns. Nothing to await, so nothing to fail on the network.
    _controller.deleteGroup(c.id).fold(
      (failure) =>
          showErrorMessage(context, failure.getLocalizedMessage(context)),
      (_) {},
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
                  _searchQuery = '';
                  _applyFilter();
                },
              ),
        hintText: S.current.strSearch,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onChanged: _onSearchChanged,
    );
  }

  /// No loading branch and no error branch — neither had anything left to
  /// describe once the read became a local `SELECT`. What is left is an empty
  /// list, which means two different things.
  Widget _buildBody() {
    if (_categories.isEmpty) {
      // Nothing the backend sends can reach `group_transactions` yet, so this
      // list can only ever be empty. Saying "no groups yet" beside an "add
      // one" button would invite the operator to create the group they already
      // created and cannot see.
      if (_searchQuery.isEmpty &&
          _controller.groupsAwaitingBackendReplication) {
        return SectionEmptyState(
          icon: Icons.cloud_sync_outlined,
          title: S.current.strAwaitingServerData,
          subtitle: S.current.strTxnGroupsAwaitingServerHint,
        );
      }
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
  final TransactionCategoriesController controller;
  final _Category? existing;

  const _CategoryEditDialog({required this.controller, this.existing});

  @override
  State<_CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends State<_CategoryEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;

  /// A form validation message, or a local write that failed. Never a
  /// connection error: nothing in this dialog touches the network.
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

  /// Synchronous: the row and its outbox operation commit before this
  /// returns, so there is no window in which the dialog waits on anything.
  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _error = null);
    final name = _nameCtrl.text.trim();
    final result = _isCreate
        ? widget.controller.createGroup(name)
        : widget.controller.updateGroup(widget.existing!.id, name);
    result.fold(
      (failure) =>
          setState(() => _error = failure.getLocalizedMessage(context)),
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
                      onPressed: () => Navigator.pop(context, false),
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
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(S.current.strCancelShort),
                    ),
                    const SizedBox(width: 6),
                    // No busy state: the save commits locally and pops. The
                    // spinner that used to live here was the network round
                    // trip, and there is no longer one to wait for.
                    ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.buttonBrand,
                        foregroundColor: colors.textOnBrand,
                        elevation: 0,
                      ),
                      child: Text(S.current.strSave),
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
