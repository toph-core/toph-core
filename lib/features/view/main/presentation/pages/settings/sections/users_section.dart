import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/theme/tokens/theme_colors.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/core/widgets/styled_virtual_keyboard.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/users/users_cubit.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/settings/widgets/section_shell.dart';
import 'package:mary_ai_pos/generated/l10n.dart';
import 'package:number_paginator/number_paginator.dart';

class UsersSection extends StatefulWidget {
  const UsersSection({super.key});

  @override
  State<UsersSection> createState() => _UsersSectionState();
}

class _UsersSectionState extends State<UsersSection> {
  static const List<int> _pageSizeOptions = [20, 50, 100];
  static const List<String> _roles = [
    'admin',
    'manager',
    'cashier',
    'waiter',
    'kitchen',
  ];

  /// Resolved as a cubit, not a repository. The section used to hold a
  /// `MainRepository` and drive its own paging, which is the coupling §7 rules
  /// out — the widget now knows about filters and rows, and nothing about where
  /// either comes from.
  final UsersCubit _cubit = inject<UsersCubit>();
  final NumberPaginatorController _paginatorController =
      NumberPaginatorController();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _paginatorController.dispose();
    _searchCtrl.dispose();
    _cubit.close();
    super.dispose();
  }

  /// No reload after save. The list is a subscription to the replica, so a
  /// write that lands locally reaches this screen the same way replication's
  /// changes do — the old `_load(page: _page)` refetch had nothing left to do.
  Future<void> _openEditor({_AdminUser? existing}) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UserEditDialog(cubit: _cubit, existing: existing),
    );
  }

  Future<void> _confirmDelete(_AdminUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(S.current.strDeleteEmployee),
        content: Text(
          S.current.strDeleteEmployeeConfirm(u.displayName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.current.strCancelShort),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            child: Text(S.current.strDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // Synchronous: the row is gone from the replica and the DELETE is queued
    // before this returns. Nothing to await, so nothing to fail on the network.
    if (!_cubit.deleteUser(u.id) && mounted) {
      showErrorMessage(context, _cubit.state.error ?? S.current.strError);
    }
  }

  /// The optimistic-update-and-roll-back dance this used to do is gone with the
  /// network call that needed it. The local write *is* the update the operator
  /// sees; if the server later refuses it, quarantine releases the row and
  /// replication reverts it — visibly, and for a stated reason.
  void _toggleActive(_AdminUser u, bool value) {
    if (!_cubit.updateUser(u.id, {'is_active': value})) {
      showErrorMessage(context, _cubit.state.error ?? S.current.strError);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<UsersCubit>.value(
      value: _cubit,
      child: BlocConsumer<UsersCubit, UsersState>(
        listenWhen: (a, b) => a.notice != b.notice && b.notice != null,
        listener: (context, state) {
          final notice = state.notice;
          if (notice == null) return;
          // Informational, not a failure: the write was accepted, it is simply
          // not on screen yet.
          showInfoMessage(context, notice);
          _cubit.acknowledge();
        },
        builder: (context, state) {
          final users = state.items.map(_AdminUser.fromJson).toList();
          return SectionShell(
            title: S.current.strRestaurantStaff,
            subtitle: state.isSearching
                ? 'Topildi: ${state.total} ta xodim'
                : (state.total == 0
                    ? S.current.strUsersRolesPerms
                    : 'Jami: ${state.total} ta xodim'),
            trailing: SectionPrimaryButton(
              icon: Icons.person_add_alt_1_rounded,
              label: S.current.strAddNewEmployee,
              onPressed: () => _openEditor(),
            ),
            child: _buildBody(state, users),
          );
        },
      ),
    );
  }

  Widget _buildBody(UsersState state, List<_AdminUser> users) {
    return Column(
      children: [
        _buildFilters(state),
        const SizedBox(height: 14),
        Expanded(child: _buildList(state, users)),
        // Shown while searching too, which it could not be before: the search
        // endpoint returned no total, so the old screen had no page count to
        // render. One local query answers filter and count together.
        if (users.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildPaginator(state),
        ],
      ],
    );
  }

  /// The debounce stays, for a different reason than before. It used to space
  /// out network requests; now it spaces out re-subscriptions, which are cheap
  /// — so it is only about not re-sorting the list under the operator's cursor
  /// on every keystroke.
  void _onSearchChanged(String v) {
    setState(() {}); // suffixIcon ko'rinishini yangilash uchun
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _cubit.setSearch(v);
    });
  }

  Widget _buildFilters(UsersState state) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onTap: () => AppScaffold.open(_searchCtrl, onChanged: _onSearchChanged),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded,
                  size: 18, color: colors.textSecondary),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: S.current.strCancel,
                      icon: Icon(Icons.close_rounded,
                          size: 18, color: colors.textSecondary),
                      onPressed: () {
                        _searchDebounce?.cancel();
                        _searchCtrl.clear();
                        setState(() {});
                        _cubit.setSearch('');
                      },
                    ),
              hintText: S.current.strSearchNameOrUsername,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: _onSearchChanged,
            onSubmitted: (v) {
              _searchDebounce?.cancel();
              _cubit.setSearch(v);
            },
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            value: state.role,
            decoration: InputDecoration(
              labelText: S.current.strRole,
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
              ..._roles.map(
                (r) => DropdownMenuItem<String?>(
                  value: r,
                  child: Text(_roleLabel(r)),
                ),
              ),
            ],
            onChanged: _cubit.setRole,
          ),
        ),
      ],
    );
  }

  /// No loading branch and no retry button. Both existed to cover a network
  /// round trip: the read is now synchronous against the replica, so there is
  /// no state between asking and having the rows, and nothing to retry.
  Widget _buildList(UsersState state, List<_AdminUser> users) {
    if (users.isEmpty) {
      if (state.isSearching) {
        return SectionEmptyState(
          icon: Icons.search_off_rounded,
          title: S.current.strNoDataFound,
          subtitle: '"${state.search}" bo\'yicha xodim topilmadi',
        );
      }
      return SectionEmptyState(
        icon: Icons.people_alt_outlined,
        title: S.current.strNoEmployeesYet,
        subtitle:
            'Ofitsiant, kassir, kassirlar va boshqaruv hisoblarini shu yerdan yarating.',
        action: SectionPrimaryButton(
          icon: Icons.person_add_alt_1_rounded,
          label: S.current.strAddFirstEmployee,
          onPressed: () => _openEditor(),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final u = users[i];
        return _UserCard(
          user: u,
          onEdit: () => _openEditor(existing: u),
          onDelete: () => _confirmDelete(u),
          onToggleActive: (v) => _toggleActive(u, v),
        );
      },
    );
  }

  Widget _buildPaginator(UsersState state) {
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
              numberPages: state.totalPages,
              initialPage: (state.page - 1).clamp(0, state.totalPages - 1),
              onPageChange: (i) => _cubit.setPage(i + 1),
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
              value: state.pageSize,
              isDense: true,
              icon: Icon(Icons.expand_more_rounded,
                  color: colors.textSecondary),
              style: TextStyle(
                fontSize: 13,
                color: colors.textDefault,
                fontWeight: FontWeight.w500,
                fontFamily: 'Inter',
              ),
              items: _pageSizeOptions
                  .map((s) => DropdownMenuItem<int>(
                        value: s,
                        child: Text(S.current.strPageSize(s)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) _cubit.setPageSize(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _UserCard extends StatefulWidget {
  final _AdminUser user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleActive;

  const _UserCard({
    required this.user,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final u = widget.user;
    final roleColor = _roleColor(u.role, colors);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
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
                color: roleColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials(u.displayName),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: roleColor,
                  fontFamily: 'Inter',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          u.displayName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textDefault,
                            fontFamily: 'Inter',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: roleColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _roleLabel(u.role),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: roleColor,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (u.username != null && u.username!.isNotEmpty)
                        '@${u.username}',
                      if (u.phoneNumber != null && u.phoneNumber!.isNotEmpty)
                        u.phoneNumber,
                    ].whereType<String>().join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: u.isActive,
              onChanged: widget.onToggleActive,
              activeColor: colors.buttonBrand,
            ),
            const SizedBox(width: 8),
            _UserActionButton(
              icon: Icons.edit_outlined,
              tooltip: S.current.strEdit,
              color: colors.buttonBrand,
              onTap: widget.onEdit,
            ),
            const SizedBox(width: 8),
            _UserActionButton(
              icon: Icons.delete_outline_rounded,
              tooltip: S.current.strDelete,
              color: colors.systemError,
              onTap: widget.onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserEditDialog extends StatefulWidget {
  final UsersCubit cubit;
  final _AdminUser? existing;

  const _UserEditDialog({required this.cubit, this.existing});

  @override
  State<_UserEditDialog> createState() => _UserEditDialogState();
}

class _UserEditDialogState extends State<_UserEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _pincodeCtrl;
  late String _role;
  late bool _isActive;
  bool _saving = false;
  String? _error;

  bool get _isCreate => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _fullNameCtrl = TextEditingController(text: e?.fullName ?? '');
    _usernameCtrl = TextEditingController(text: e?.username ?? '');
    _phoneCtrl = TextEditingController(text: e?.phoneNumber ?? '+998');
    _emailCtrl = TextEditingController(text: e?.email ?? '');
    _passwordCtrl = TextEditingController();
    _pincodeCtrl = TextEditingController();
    _role = e?.role ?? 'waiter';
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _pincodeCtrl.dispose();
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Majburiy' : null;

  String? _validatePhone(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Majburiy';
    if (s.length != 13 || !s.startsWith('+998')) {
      return '+998XXXXXXXXX formatida';
    }
    if (!RegExp(r'^\+998\d{9}$').hasMatch(s)) {
      return '+998XXXXXXXXX formatida';
    }
    return null;
  }

  String? _validateCreatePassword(String? v) {
    if (!_isCreate) return null;
    final s = v?.trim() ?? '';
    if (s.length < 4) return 'Kamida 4 ta belgi';
    return null;
  }

  /// Not a `Future` any more, and `_saving` never becomes true for long enough
  /// to render: the write commits locally and returns. The double-submit guard
  /// stays because a fast second tap is still a second write.
  ///
  /// The two bodies keep their different key styles — `fullName` for register,
  /// `full_name` for update — because they are two different endpoints' request
  /// shapes, and the request is what the outbox replays. Only the update body
  /// doubles as a local row, and only its keys have to match the server's.
  void _save() {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final ok = _isCreate
        // snake_case, matching `model.CreateStaffRequest`. The camelCase
        // keys this used to send bound to nothing on the server — the create
        // was rejected with "full_name is required" — and, because the same
        // map is stored verbatim as the provisional local row, the new staff
        // member also showed up nameless in the list until replication
        // overwrote them.
        ? widget.cubit.createUser({
            'full_name': _fullNameCtrl.text.trim(),
            'phone_number': _phoneCtrl.text.trim(),
            'username': _usernameCtrl.text.trim(),
            'password': _passwordCtrl.text.trim(),
            if (_pincodeCtrl.text.trim().isNotEmpty)
              'pincode': _pincodeCtrl.text.trim(),
            'role': _role,
          })
        : widget.cubit.updateUser(widget.existing!.id, {
            'full_name': _fullNameCtrl.text.trim(),
            'username': _usernameCtrl.text.trim(),
            'phone_number': _phoneCtrl.text.trim(),
            if (_emailCtrl.text.trim().isNotEmpty)
              'email': _emailCtrl.text.trim(),
            if (_pincodeCtrl.text.trim().isNotEmpty)
              'pincode': _pincodeCtrl.text.trim(),
            'is_active': _isActive,
          });

    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = widget.cubit.state.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.bgDefault,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
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
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: colors.buttonBrand.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _isCreate
                            ? Icons.person_add_alt_1_rounded
                            : Icons.edit_outlined,
                        color: colors.buttonBrand,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isCreate ? S.current.strAddNewEmployee : 'Xodimni tahrirlash',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.textDefault,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed:
                          _saving ? null : () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close_rounded),
                      color: colors.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _field(
                  label: S.current.strFullName,
                  controller: _fullNameCtrl,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        label: S.current.strUsername,
                        controller: _usernameCtrl,
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        label: S.current.strPhone,
                        controller: _phoneCtrl,
                        hint: '+998901234567',
                        keyboard: TextInputType.phone,
                        formatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                          LengthLimitingTextInputFormatter(13),
                        ],
                        validator: _validatePhone,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isCreate)
                  _field(
                    label: S.current.strPassword,
                    controller: _passwordCtrl,
                    obscure: true,
                    validator: _validateCreatePassword,
                  )
                else
                  _field(
                    label: S.current.strEmail,
                    controller: _emailCtrl,
                    keyboard: TextInputType.emailAddress,
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        label: S.current.strPinOptional,
                        controller: _pincodeCtrl,
                        keyboard: TextInputType.number,
                        formatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            S.current.strRole,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colors.textSecondary,
                              fontFamily: 'Inter',
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: _role,
                            decoration: InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            items: _UsersSectionState._roles
                                .map((r) => DropdownMenuItem<String>(
                                      value: r,
                                      child: Text(_roleLabel(r)),
                                    ))
                                .toList(),
                            onChanged: _isCreate
                                ? (v) => setState(() => _role = v ?? _role)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!_isCreate) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Switch.adaptive(
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        activeColor: colors.buttonBrand,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isActive ? 'Faol' : 'Faol emas',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textDefault,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.systemError.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colors.systemError.withOpacity(0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            size: 16, color: colors.systemError),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.systemError,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _saving ? null : () => Navigator.pop(context, false),
                      child: Text(
                        S.current.strCancelShort,
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.buttonBrand,
                        foregroundColor: colors.textOnBrand,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : Text(_isCreate ? 'Yaratish' : S.current.strSave),
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

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool obscure = false,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
  }) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colors.textSecondary,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 6),
        Builder(
          builder: (fieldContext) => TextFormField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboard,
            inputFormatters: formatters,
            validator: validator,
            onTap: () => FloatingKeyboard.openFor(
              fieldContext,
              controller,
              keyboardType: keyboard,
            ),
            decoration: InputDecoration(
              hintText: hint,
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

String _roleLabel(String role) {
  switch (role) {
    case 'admin':
      return 'Admin';
    case 'manager':
      return 'Menejer';
    case 'cashier':
      return 'Kassir';
    case 'waiter':
      return 'Ofitsiant';
    case 'kitchen':
      return 'Oshpaz';
    case 'superadmin':
      return 'Superadmin';
    default:
      return role;
  }
}

Color _roleColor(String role, ThemeColors colors) {
  switch (role) {
    case 'admin':
    case 'superadmin':
      return const Color(0xFFDC2626);
    case 'manager':
      return const Color(0xFF7C3AED);
    case 'cashier':
      return const Color(0xFF3B82F6);
    case 'waiter':
      return const Color(0xFF22C55E);
    case 'kitchen':
      return const Color(0xFFFB6633);
    default:
      return colors.textSecondary;
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

class _AdminUser {
  final String id;
  final String? fullName;
  final String? username;
  final String role;
  final bool isActive;
  final String? email;
  final String? phoneNumber;

  const _AdminUser({
    required this.id,
    required this.role,
    required this.isActive,
    this.fullName,
    this.username,
    this.email,
    this.phoneNumber,
  });

  String get displayName {
    if (fullName != null && fullName!.isNotEmpty) return fullName!;
    if (username != null && username!.isNotEmpty) return username!;
    return 'No name';
  }

  factory _AdminUser.fromJson(Map<String, dynamic> json) {
    return _AdminUser(
      id: (json['id'] ?? '').toString(),
      fullName: json['full_name']?.toString(),
      username: json['username']?.toString(),
      role: (json['role'] ?? 'waiter').toString(),
      isActive: json['is_active'] == true,
      email: json['email']?.toString(),
      phoneNumber: json['phone_number']?.toString(),
    );
  }
}

class _UserActionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _UserActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  State<_UserActionButton> createState() => _UserActionButtonState();
}

class _UserActionButtonState extends State<_UserActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: widget.color.withOpacity(_hover ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(widget.icon, size: 22, color: widget.color),
            ),
          ),
        ),
      ),
    );
  }
}
