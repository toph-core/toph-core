import 'dart:async';

import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/extension/date_time_extension.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/theme/tokens/theme_colors.dart';
import 'package:mary_ai_pos/core/utils/app_formatter.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/core/widgets/styled_virtual_keyboard.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/transactions_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/settings/widgets/section_shell.dart';
import 'package:mary_ai_pos/generated/l10n.dart';
import 'package:number_paginator/number_paginator.dart';

enum _TxType { income, expense, transferIncome, transferExpense }

extension on _TxType {
  String get apiValue {
    switch (this) {
      case _TxType.income:
        return 'income';
      case _TxType.expense:
        return 'expense';
      case _TxType.transferIncome:
        return 'transfer_income';
      case _TxType.transferExpense:
        return 'transfer_expense';
    }
  }

  String label() {
    switch (this) {
      case _TxType.income:
        return S.current.strIncome;
      case _TxType.expense:
        return S.current.strExpense;
      case _TxType.transferIncome:
      case _TxType.transferExpense:
        return S.current.strTxnTransfer;
    }
  }

  Color color(ThemeColors colors) {
    switch (this) {
      case _TxType.income:
      case _TxType.transferIncome:
        return const Color(0xFF16A34A);
      case _TxType.expense:
      case _TxType.transferExpense:
        return const Color(0xFFDC2626);
    }
  }

  bool get isIncome => this == _TxType.income || this == _TxType.transferIncome;
}

class TransactionsListSection extends StatefulWidget {
  const TransactionsListSection({super.key});

  @override
  State<TransactionsListSection> createState() =>
      _TransactionsListSectionState();
}

class _TransactionsListSectionState extends State<TransactionsListSection> {
  static const List<int> _pageSizeOptions = [20, 50, 100];

  final MainRepository _repository = inject<MainRepository>();
  final TransactionsRepository _transactionsRepository =
      inject<TransactionsRepository>();
  final NumberPaginatorController _paginatorController =
      NumberPaginatorController();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<_Transaction> _transactions = const [];
  List<_Option> _cashRegisters = const [];
  List<_Option> _categories = const [];
  StreamSubscription<List<Map<String, dynamic>>>? _cashRegistersSub;
  StreamSubscription<List<Map<String, dynamic>>>? _groupsSub;

  int _page = 1;
  int _pageSize = 20;
  int? _totalCount;
  String? _typeFilter;
  String? _cashRegisterFilter;
  String _searchQuery = '';
  Timer? _searchDebounce;

  int get _totalPages {
    final t = _totalCount;
    if (t == null || t <= 0) return 1;
    final p = (t + _pageSize - 1) ~/ _pageSize;
    return p > 0 ? p : 1;
  }

  @override
  void initState() {
    super.initState();
    _loadOptions();
    _load(page: 1);
  }

  @override
  void dispose() {
    _cashRegistersSub?.cancel();
    _groupsSub?.cancel();
    _searchDebounce?.cancel();
    _paginatorController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// offline-first-target-architecture.md §8 Phase 5: reactive reads over
  /// TransactionsRepository/LocalDatabase (already hydrated by SyncEngine,
  /// §8 Phase 1) instead of a fetch-on-init — both are small filter/picker
  /// option lists, not the paginated ledger itself (`_load` below, which
  /// stays a direct paginated `MainRepository.getTransactions` call — no
  /// bounded local mirror to page through instead, same reasoning already
  /// used elsewhere in this codebase for live search).
  void _loadOptions() {
    _cashRegistersSub = _transactionsRepository.watchCashRegisters().listen((registers) {
      if (!mounted) return;
      setState(() => _cashRegisters = registers.map(_Option.fromJson).toList());
    });
    _groupsSub = _transactionsRepository.watchTransactionGroups().listen((groups) {
      if (!mounted) return;
      setState(() => _categories = groups.map(_Option.fromJson).toList());
    });
  }

  Future<void> _load({required int page}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _repository.getTransactions(
      limit: _pageSize,
      offset: (page - 1) * _pageSize,
      search: _searchQuery.isEmpty ? null : _searchQuery,
      type: _typeFilter,
      cashRegisterId: _cashRegisterFilter,
    );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _loading = false;
        _error = failure.getLocalizedMessage(context);
      }),
      (data) => setState(() {
        _transactions = data.items.map(_Transaction.fromJson).toList();
        _totalCount = data.total;
        _page = page;
        _loading = false;
      }),
    );
  }

  String _optionName(List<_Option> options, String? id) {
    if (id == null) return '';
    return options
        .firstWhere(
          (o) => o.id == id,
          orElse: () => const _Option(id: '', name: ''),
        )
        .name;
  }

  Future<void> _openCreateDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TransactionEditDialog(
        repository: _repository,
        cashRegisters: _cashRegisters,
        categories: _categories,
      ),
    );
    if (saved == true && mounted) _load(page: 1);
  }

  Future<void> _openEditDialog(_Transaction tx) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TransactionEditDialog(
        repository: _repository,
        cashRegisters: _cashRegisters,
        categories: _categories,
        existing: tx,
      ),
    );
    if (saved == true && mounted) _load(page: _page);
  }

  Future<void> _confirmDelete(_Transaction tx) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(S.current.strDeleteTransaction),
        content: Text(S.current.strDeleteTransactionConfirm),
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
    final result = await _repository.deleteTransaction(tx.id);
    if (!mounted) return;
    result.fold(
      (failure) => showErrorMessage(context, failure.getLocalizedMessage(context)),
      (_) => _load(page: _page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionShell(
      title: S.current.strTransactions,
      subtitle: _totalCount == null
          ? null
          : S.current.strTotalCount(_totalCount!),
      trailing: SectionPrimaryButton(
        icon: Icons.add_rounded,
        label: S.current.strAddTransaction,
        onPressed: _openCreateDialog,
      ),
      child: Column(
        children: [
          _buildFilters(),
          const SizedBox(height: 14),
          Expanded(child: _buildBody()),
          if (_transactions.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildPaginator(),
          ],
        ],
      ),
    );
  }

  void _onSearchChanged(String v) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _searchQuery = v.trim());
      _load(page: 1);
    });
  }

  Widget _buildFilters() {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onTap: () =>
                AppScaffold.open(_searchCtrl, onChanged: _onSearchChanged),
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
                        _load(page: 1);
                      },
                    ),
              hintText: S.current.strSearch,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String?>(
            value: _typeFilter,
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(S.current.strAllRoles),
              ),
              ..._TxType.values.map(
                (t) => DropdownMenuItem<String?>(
                  value: t.apiValue,
                  child: Text(t.label()),
                ),
              ),
            ],
            onChanged: (v) {
              setState(() => _typeFilter = v);
              _load(page: 1);
            },
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            value: _cashRegisterFilter,
            decoration: InputDecoration(
              labelText: S.current.strCashRegister,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(S.current.strAllRoles),
              ),
              ..._cashRegisters.map(
                (o) =>
                    DropdownMenuItem<String?>(value: o.id, child: Text(o.name)),
              ),
            ],
            onChanged: (v) {
              setState(() => _cashRegisterFilter = v);
              _load(page: 1);
            },
          ),
        ),
      ],
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
              onPressed: () => _load(page: _page),
            ),
          ],
        ),
      );
    }
    if (_transactions.isEmpty) {
      return SectionEmptyState(
        icon: Icons.receipt_long_outlined,
        title: S.current.strNoTransactionsYet,
        action: SectionPrimaryButton(
          icon: Icons.add_rounded,
          label: S.current.strAddTransaction,
          onPressed: _openCreateDialog,
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _transactions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final tx = _transactions[i];
        final canEdit = tx.type == _TxType.income || tx.type == _TxType.expense;
        return _TransactionCard(
          tx: tx,
          cashRegisterName:
              tx.type == _TxType.transferIncome ||
                  tx.type == _TxType.transferExpense
              ? '${_optionName(_cashRegisters, tx.fromCashRegisterId)} → ${_optionName(_cashRegisters, tx.toCashRegisterId)}'
              : _optionName(_cashRegisters, tx.cashRegisterId),
          categoryName: _optionName(_categories, tx.groupTransactionId),
          onEdit: canEdit ? () => _openEditDialog(tx) : null,
          onDelete: () => _confirmDelete(tx),
        );
      },
    );
  }

  Widget _buildPaginator() {
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              secondary: colors.buttonBrand,
              onSecondary: colors.textOnBrand,
            ),
          ),
          child: SizedBox(
            width: 372,
            height: 44,
            child: NumberPaginator(
              controller: _paginatorController,
              numberPages: _totalPages,
              initialPage: (_page - 1).clamp(0, _totalPages - 1),
              onPageChange: (i) {
                if (_loading) return;
                _load(page: i + 1);
              },
              child: const SizedBox(
                height: 40,
                child: Row(
                  children: [
                    PrevButton(),
                    Expanded(child: NumberContent()),
                    NextButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colors.bgSecondary,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _pageSize,
              isDense: true,
              icon: Icon(
                Icons.expand_more_rounded,
                color: colors.textSecondary,
              ),
              items: _pageSizeOptions
                  .map(
                    (s) => DropdownMenuItem<int>(
                      value: s,
                      child: Text(S.current.strPageSize(s)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null || v == _pageSize || _loading) return;
                setState(() => _pageSize = v);
                _load(page: 1);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TransactionCard extends StatefulWidget {
  final _Transaction tx;
  final String cashRegisterName;
  final String categoryName;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  const _TransactionCard({
    required this.tx,
    required this.cashRegisterName,
    required this.categoryName,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_TransactionCard> createState() => _TransactionCardState();
}

class _TransactionCardState extends State<_TransactionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tx = widget.tx;
    final typeColor = tx.type.color(colors);
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
                color: typeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                tx.type.isIncome
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                size: 20,
                color: typeColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tx.type.label(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: typeColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          [
                            if (widget.cashRegisterName.isNotEmpty)
                              widget.cashRegisterName,
                            tx.date.toYyyyMmDd,
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.sell_outlined,
                        size: 14,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${S.current.strTxnGroupLabel}: ${widget.categoryName.isNotEmpty ? widget.categoryName : '—'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: widget.categoryName.isNotEmpty
                              ? colors.textDefault
                              : colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.comment_outlined,
                        size: 14,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          (tx.description != null && tx.description!.isNotEmpty)
                              ? tx.description!
                              : '—',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                (tx.description != null &&
                                    tx.description!.isNotEmpty)
                                ? colors.textDefault
                                : colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              '${tx.type.isIncome ? '+' : '-'}${tx.amount}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: typeColor,
              ),
            ),
            const SizedBox(width: 8),
            if (widget.onEdit != null)
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

class _TransactionEditDialog extends StatefulWidget {
  final MainRepository repository;
  final List<_Option> cashRegisters;
  final List<_Option> categories;
  final _Transaction? existing;

  const _TransactionEditDialog({
    required this.repository,
    required this.cashRegisters,
    required this.categories,
    this.existing,
  });

  @override
  State<_TransactionEditDialog> createState() => _TransactionEditDialogState();
}

class _TransactionEditDialogState extends State<_TransactionEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  late final TextEditingController _descriptionCtrl;

  late bool _isTransfer;
  late _TxType _createType;
  String? _cashRegisterId;
  String? _fromCashRegisterId;
  String? _toCashRegisterId;
  String? _categoryId;
  String _payType = 'cash';
  late DateTime _date;
  bool _saving = false;
  String? _error;

  bool get _isCreate => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amountCtrl = TextEditingController(
      text: AppFormatter.formatPriceIntegerSpaces(e?.amount),
    );
    _descriptionCtrl = TextEditingController(text: e?.description ?? '');
    _isTransfer = false;
    _createType = _TxType.income;
    _cashRegisterId = e?.cashRegisterId;
    _fromCashRegisterId = e?.fromCashRegisterId;
    _toCashRegisterId = e?.toCashRegisterId;
    _categoryId = e?.groupTransactionId;
    _payType = e?.payType ?? 'cash';
    _date = e?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    FloatingKeyboard.close();
    _amountCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  String get _rawAmount =>
      _amountCtrl.text.replaceAll(RegExp(r'\s'), '').trim();

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isCreate) {
      if (_isTransfer) {
        if (_fromCashRegisterId == null || _toCashRegisterId == null) {
          setState(() => _error = S.current.strRequiredFieldsMissing);
          return;
        }
      } else if (_cashRegisterId == null) {
        setState(() => _error = S.current.strRequiredFieldsMissing);
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final Either<Failure, bool> result;
    if (_isCreate) {
      if (_isTransfer) {
        result = await widget.repository.createTransferTransaction({
          'from_cash_register_id': _fromCashRegisterId,
          'to_cash_register_id': _toCashRegisterId,
          if (_categoryId != null) 'group_transaction_id': _categoryId,
          'amount': _rawAmount,
          'description': _descriptionCtrl.text.trim(),
          'pay_type': _payType,
          'date': _toApiDateTime(_date),
        });
      } else {
        result = await widget.repository.createIncomeExpenseTransaction({
          'type': _createType.apiValue,
          'cash_register_id': _cashRegisterId,
          if (_categoryId != null) 'group_transaction_id': _categoryId,
          'amount': _rawAmount,
          'description': _descriptionCtrl.text.trim(),
          'pay_type': _payType,
          'date': _toApiDateTime(_date),
        });
      }
    } else {
      result = await widget.repository.updateTransaction(
        widget.existing!.id,
        {
          'amount': _rawAmount,
          'description': _descriptionCtrl.text.trim(),
          'pay_type': _payType,
          'date': _toApiDateTime(_date),
        },
      );
    }
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
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 24, left: 40, right: 40),
      backgroundColor: colors.bgDefault,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isCreate
                              ? S.current.strAddTransaction
                              : S.current.strEditTransaction,
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
                  if (_isCreate) ...[
                    _typeSelector(colors),
                    const SizedBox(height: 12),
                  ],
                  if (_isCreate && _isTransfer) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _cashRegisterDropdown(
                            label: S.current.strFromCashRegister,
                            value: _fromCashRegisterId,
                            onChanged: (v) =>
                                setState(() => _fromCashRegisterId = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _cashRegisterDropdown(
                            label: S.current.strToCashRegister,
                            value: _toCashRegisterId,
                            onChanged: (v) =>
                                setState(() => _toCashRegisterId = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ] else if (_isCreate) ...[
                    _cashRegisterDropdown(
                      label: S.current.strCashRegister,
                      value: _cashRegisterId,
                      onChanged: (v) => setState(() => _cashRegisterId = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _field(
                    label: S.current.strAmount,
                    controller: _amountCtrl,
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    numeric: true,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? S.current.strFieldRequired
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    label: S.current.strDescription,
                    controller: _descriptionCtrl,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              S.current.strPayType,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              value: _payType,
                              decoration: InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'cash',
                                  child: Text(S.current.strCash),
                                ),
                                DropdownMenuItem(
                                  value: 'card',
                                  child: Text(S.current.strCard),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _payType = v ?? _payType),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (_isCreate)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                S.current.strTxnGroupLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String?>(
                                value: _categoryId,
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                items: [
                                  DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text(S.current.strAllRoles),
                                  ),
                                  ...widget.categories.map(
                                    (o) => DropdownMenuItem<String?>(
                                      value: o.id,
                                      child: Text(o.name),
                                    ),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _categoryId = v),
                              ),
                            ],
                          ),
                        )
                      else
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                S.current.strDate,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: _pickDate,
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: Text(_date.toYyyyMmDd),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (_isCreate) ...[
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.current.strDate,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: _pickDate,
                          child: InputDecorator(
                            decoration: InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(_date.toYyyyMmDd),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.systemError.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colors.systemError.withOpacity(0.35),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.systemError,
                        ),
                      ),
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
      ),
    );
  }

  Widget _typeSelector(ThemeColors colors) {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? colors.buttonBrand.withOpacity(0.12)
                  : colors.bgSecondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? colors.buttonBrand : colors.border,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? colors.buttonBrand : colors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(
          S.current.strIncome,
          !_isTransfer && _createType == _TxType.income,
          () => setState(() {
            _isTransfer = false;
            _createType = _TxType.income;
          }),
        ),
        chip(
          S.current.strExpense,
          !_isTransfer && _createType == _TxType.expense,
          () => setState(() {
            _isTransfer = false;
            _createType = _TxType.expense;
          }),
        ),
        chip(
          S.current.strTxnTransfer,
          _isTransfer,
          () => setState(() => _isTransfer = true),
        ),
      ],
    );
  }

  Widget _cashRegisterDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          items: widget.cashRegisters
              .map(
                (o) =>
                    DropdownMenuItem<String>(value: o.id, child: Text(o.name)),
              )
              .toList(),
          onChanged: onChanged,
          validator: (_) => value == null ? S.current.strFieldRequired : null,
        ),
      ],
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboard,
    String? Function(String?)? validator,
    bool numeric = false,
  }) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
        const SizedBox(height: 6),
        Builder(
          builder: (fieldContext) => TextFormField(
            controller: controller,
            keyboardType: keyboard,
            validator: validator,
            readOnly: true,
            showCursor: true,
            textAlign: numeric ? TextAlign.right : TextAlign.left,
            onTap: () {
              if (numeric) {
                FloatingKeyboard.openNumeric(
                  fieldContext,
                  controller,
                  groupThousands: true,
                );
              } else {
                FloatingKeyboard.openText(context, controller);
              }
            },
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Option {
  final String id;
  final String name;
  const _Option({required this.id, required this.name});

  factory _Option.fromJson(Map<String, dynamic> json) => _Option(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
  );
}

class _Transaction {
  final String id;
  final _TxType type;
  final String? cashRegisterId;
  final String? fromCashRegisterId;
  final String? toCashRegisterId;
  final String? groupTransactionId;
  final String amount;
  final String? description;
  final String? payType;
  final DateTime date;

  const _Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    this.cashRegisterId,
    this.fromCashRegisterId,
    this.toCashRegisterId,
    this.groupTransactionId,
    this.description,
    this.payType,
  });

  factory _Transaction.fromJson(Map<String, dynamic> json) {
    final type =
        _txTypeFromApi(json['type']?.toString() ?? '') ?? _TxType.expense;
    return _Transaction(
      id: (json['id'] ?? '').toString(),
      type: type,
      cashRegisterId: json['cash_register_id']?.toString(),
      fromCashRegisterId: json['from_cash_register_id']?.toString(),
      toCashRegisterId: json['to_cash_register_id']?.toString(),
      groupTransactionId: json['group_transaction_id']?.toString(),
      amount: (json['amount'] ?? '0').toString(),
      description: json['description']?.toString(),
      payType: json['pay_type']?.toString(),
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// Serializes a date picked in the local timezone as an RFC3339 string with a
/// `Z` suffix, keeping the same calendar date/time components — Go's
/// `time.Time` JSON unmarshaling rejects an offset-less ISO string (the plain
/// `DateTime.toIso8601String()` omits it for non-UTC values).
String _toApiDateTime(DateTime d) => DateTime.utc(
  d.year,
  d.month,
  d.day,
  d.hour,
  d.minute,
  d.second,
  d.millisecond,
).toIso8601String();

_TxType? _txTypeFromApi(String v) {
  switch (v) {
    case 'income':
      return _TxType.income;
    case 'expense':
      return _TxType.expense;
    case 'transfer_income':
      return _TxType.transferIncome;
    case 'transfer_expense':
      return _TxType.transferExpense;
  }
  return null;
}
