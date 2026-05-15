import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/design_system/pos_design_system.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/utils/user_role_permissions.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/main_header.dart';
import 'package:mary_ai_pos/features/view/main/presentation/widgets/product_grid_card.dart';
import 'package:mary_ai_pos/generated/l10n.dart';
import 'package:number_paginator/number_paginator.dart';
import 'package:virtual_keyboard_multi_language/virtual_keyboard_multi_language.dart';

/// Admin/manager: kategoriyalar + taomlar ikkita panel ko'rinishida.
class MenuMealsListScreen extends StatefulWidget {
  const MenuMealsListScreen({super.key});

  @override
  State<MenuMealsListScreen> createState() => _MenuMealsListScreenState();
}

class _MenuMealsListScreenState extends State<MenuMealsListScreen> {
  final DioClient _client = inject<DioClient>();
  final NumberPaginatorController _paginatorController =
      NumberPaginatorController();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _catSearchCtrl = TextEditingController();

  // null = klaviatura yashirin. Non-null = qaysi controller'ga yozish kerakligi.
  final ValueNotifier<TextEditingController?> _kbTarget = ValueNotifier(null);

  static const List<int> _pageSizeOptions = [20, 50, 100];
  int _pageSize = 20;

  List<CategoryModel> _categories = const [];
  List<GoodsModel> _goods = const [];
  String? _selectedCategoryId; // null = barcha taomlar
  bool _loadingCategories = true;
  bool _loadingGoods = true;
  String? _errorGoods;
  int _page = 1;
  int? _totalCount;
  String _searchQuery = '';

  int get _totalPages {
    final total = _totalCount;
    if (total == null || total <= 0) return 1;
    final p = (total + _pageSize - 1) ~/ _pageSize;
    return p > 0 ? p : 1;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final role = context.read<UserBloc>().state.userMOdel?.role;
      if (role.canManageMenu) _loadAll();
    });
  }

  @override
  void dispose() {
    _paginatorController.dispose();
    _searchCtrl.dispose();
    _catSearchCtrl.dispose();
    _kbTarget.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await _loadCategories();
    await _loadGoods(page: 1);
  }

  // ── Categories ──────────────────────────────

  Future<void> _loadCategories() async {
    if (!mounted) return;
    setState(() => _loadingCategories = true);
    try {
      final res = await _client.get(ListAPI.categories);
      final list =
          (res.data['data'] as List?)
              ?.map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <CategoryModel>[];
      if (!mounted) return;
      setState(() {
        _categories = list;
        _loadingCategories = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCategories = false);
    }
  }

  Future<void> _createCategory(String name) async {
    await _client.post(ListAPI.categories, data: {'name': name});
    await _loadCategories();
  }

  void _openCategoryDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => _CategoryDialog(
        onCreate: (name) async {
          try {
            await _createCategory(name);
          } catch (e) {
            if (!mounted) return;
            _showSnack(
              e is DioException
                  ? (e.response?.data['message']?.toString() ??
                        "Kategoriya qo'shilmadi")
                  : "Kategoriya qo'shilmadi",
            );
          }
        },
      ),
    );
  }

  // ── Goods ────────────────────────────────────

  Future<void> _loadGoods({required int page}) async {
    if (!mounted) return;
    setState(() {
      _loadingGoods = true;
      _errorGoods = null;
    });
    try {
      final offset = (page - 1) * _pageSize;
      final params = <String, dynamic>{'limit': _pageSize, 'offset': offset};
      if (_selectedCategoryId != null) {
        params['category_id'] = _selectedCategoryId;
      }
      if (_searchQuery.isNotEmpty) {
        params['query'] = _searchQuery;
      }
      final res = await _client.get(ListAPI.goods, queryParameters: params);
      final list = _extractGoodsList(res.data);
      final total = _extractTotalCount(res.data);
      if (!mounted) return;
      setState(() {
        _goods = list;
        _page = page;
        _totalCount = total;
        _loadingGoods = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingGoods = false;
        _errorGoods = e.response?.data is Map
            ? e.response!.data['message']?.toString()
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingGoods = false;
        _errorGoods = "Taomlar yuklanmadi";
      });
    }
  }

  Future<void> _openManage({String? mealId}) async {
    await Navigator.pushNamed(
      context,
      AppRoutes.menuManageScreen,
      arguments: mealId == null ? null : {'meal_id': mealId},
    );
    if (!mounted) return;
    await _loadGoods(page: _page);
  }

  void _showSnack(String msg, {bool success = false}) {
    if (success) {
      showSuccessMessage(context, msg);
    } else {
      showErrorMessage(context, msg);
    }
  }

  List<GoodsModel> _extractGoodsList(dynamic raw) {
    dynamic source = raw;
    if (source is Map<String, dynamic>) {
      source =
          source['data'] ?? source['items'] ?? source['results'] ?? const [];
    }
    if (source is Map<String, dynamic>) {
      source =
          source['items'] ?? source['results'] ?? source['data'] ?? const [];
    }
    if (source is! List) return const [];
    return source
        .whereType<Map>()
        .map((e) => GoodsModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  int? _extractTotalCount(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    for (final c in [
      raw['count'],
      raw['total'],
      raw['meta'] is Map ? (raw['meta'] as Map)['total'] : null,
      raw['pagination'] is Map ? (raw['pagination'] as Map)['total'] : null,
    ]) {
      if (c is num) return c.toInt();
      if (c is String) {
        final p = int.tryParse(c);
        if (p != null) return p;
      }
    }
    return null;
  }

  // ── Build ────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      activeRoute: AppRoutes.menuMealsScreen,
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (_kbTarget.value != null) _kbTarget.value = null;
            },
            child: Column(
              children: [
                MainHeader(title: S.current.strMenu),
                Expanded(
                  child: BlocBuilder<UserBloc, UserState>(
                    buildWhen: (p, c) => p.userMOdel?.role != c.userMOdel?.role,
                    builder: (context, userState) {
                      final allowed =
                          userState.userMOdel?.role.canManageMenu ?? false;
                      final colors = context.colors;
                      if (!allowed) {
                        return Center(
                          child: Text(
                            'Faqat admin, menejer va superadmin kirishi mumkin',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Chap panel: Kategoriyalar ──
                          SizedBox(
                            width: 260,
                            child: _CategoriesPanel(
                              categories: _categories,
                              loading: _loadingCategories,
                              selectedId: _selectedCategoryId,
                              searchCtrl: _catSearchCtrl,
                              keyboardTarget: _kbTarget,
                              onSelect: (id) {
                                setState(() {
                                  _selectedCategoryId = id;
                                  _searchQuery = '';
                                  _searchCtrl.clear();
                                });
                                _loadGoods(page: 1);
                              },
                              onAdd: () => _openCategoryDialog(),
                            ),
                          ),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: colors.border,
                          ),
                          // ── O'ng panel: Taomlar ──
                          Expanded(
                            child: _GoodsPanel(
                              goods: _goods,
                              categories: _categories,
                              loading: _loadingGoods,
                              error: _errorGoods,
                              page: _page,
                              totalCount: _totalCount ?? 0,
                              totalPages: _totalPages,
                              pageSize: _pageSize,
                              pageSizeOptions: _pageSizeOptions,
                              paginatorController: _paginatorController,
                              searchCtrl: _searchCtrl,
                              keyboardTarget: _kbTarget,
                              selectedCategoryId: _selectedCategoryId,
                              onSearch: (q) {
                                setState(() => _searchQuery = q);
                                _loadGoods(page: 1);
                              },
                              onPageChange: (p) => _loadGoods(page: p),
                              onPageSizeChange: (sz) {
                                setState(() => _pageSize = sz);
                                _loadGoods(page: 1);
                              },
                              onEdit: (g) => _openManage(mealId: g.id),
                              onNew: () => _openManage(),
                              onRetry: () => _loadGoods(page: _page),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Virtual keyboard overlay
          ValueListenableBuilder<TextEditingController?>(
            valueListenable: _kbTarget,
            builder: (context, ctrl, _) {
              if (ctrl == null) return const SizedBox.shrink();
              return Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: context.colors.bgSecondary),
                  child: SafeArea(
                    child: VirtualKeyboard(
                      height: context.h * .3,
                      customLayoutKeys: VirtualKeyboardDefaultLayoutKeys([
                        VirtualKeyboardDefaultLayouts.English,
                      ]),
                      textColor: Colors.black,
                      fontSize: 24,
                      textController: ctrl,
                      type: VirtualKeyboardType.Alphanumeric,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// CHAP PANEL — Kategoriyalar
// ═══════════════════════════════════════════════════════

class _CategoriesPanel extends StatefulWidget {
  final List<CategoryModel> categories;
  final bool loading;
  final String? selectedId;
  final TextEditingController searchCtrl;
  final ValueNotifier<TextEditingController?> keyboardTarget;
  final void Function(String? id) onSelect;
  final VoidCallback onAdd;

  const _CategoriesPanel({
    required this.categories,
    required this.loading,
    required this.selectedId,
    required this.searchCtrl,
    required this.keyboardTarget,
    required this.onSelect,
    required this.onAdd,
  });

  @override
  State<_CategoriesPanel> createState() => _CategoriesPanelState();
}

class _CategoriesPanelState extends State<_CategoriesPanel> {
  String _catSearch = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final filtered = _catSearch.isEmpty
        ? widget.categories
        : widget.categories
              .where(
                (cat) =>
                    cat.name.toLowerCase().contains(_catSearch.toLowerCase()),
              )
              .toList();

    return Container(
      color: c.bgDefault,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Row(
              children: [
                Text(
                  'Kategoriyalar',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.textDefault,
                    fontFamily: 'Inter',
                  ),
                ),
                // const Spacer(),
                // _IconBtn(
                //   icon: Icons.add_rounded,
                //   tooltip: S.current.strAddCategory,
                //   color: c.textBrand,
                //   onTap: widget.onAdd,
                // ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: _SearchField(
              hint: 'Qidirish...',
              large: true,
              controller: widget.searchCtrl,
              keyboardTarget: widget.keyboardTarget,
              onChanged: (v) => setState(() => _catSearch = v),
            ),
          ),
          const SizedBox(height: 4),
          // "Barcha taomlar" item
          _CatItem(
            label: S.current.strAllDishes,
            icon: Icons.restaurant_menu_rounded,
            selected: widget.selectedId == null,
            onTap: () => widget.onSelect(null),
          ),
          Expanded(
            child: widget.loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Kategoriya topilmadi',
                      style: TextStyle(
                        fontSize: 12,
                        color: c.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final cat = filtered[i];
                      return _CatItemWithActions(
                        cat: cat,
                        selected: widget.selectedId == cat.id,
                        onTap: () => widget.onSelect(cat.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CatItem extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _CatItem({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = selected ? c.textBrand.withOpacity(0.10) : Colors.transparent;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon!,
                size: 20,
                color: selected ? c.textBrand : c.textSecondary,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? c.textBrand : c.textDefault,
                  fontFamily: 'Inter',
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatItemWithActions extends StatelessWidget {
  final CategoryModel cat;
  final bool selected;
  final VoidCallback onTap;

  const _CatItemWithActions({
    required this.cat,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = selected ? c.textBrand.withOpacity(0.10) : Colors.transparent;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? c.textBrand : c.textTertiary.withOpacity(0.5),
              ),
            ),
            Expanded(
              child: Text(
                cat.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? c.textBrand : c.textDefault,
                  fontFamily: 'Inter',
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// O'NG PANEL — Taomlar
// ═══════════════════════════════════════════════════════

class _GoodsPanel extends StatelessWidget {
  final List<GoodsModel> goods;
  final List<CategoryModel> categories;
  final bool loading;
  final String? error;
  final int page;
  final int totalCount;
  final int totalPages;
  final int pageSize;
  final List<int> pageSizeOptions;
  final NumberPaginatorController paginatorController;
  final TextEditingController searchCtrl;
  final ValueNotifier<TextEditingController?> keyboardTarget;
  final String? selectedCategoryId;
  final void Function(String) onSearch;
  final void Function(int) onPageChange;
  final void Function(int) onPageSizeChange;
  final void Function(GoodsModel) onEdit;
  final VoidCallback onNew;
  final VoidCallback onRetry;

  const _GoodsPanel({
    required this.goods,
    required this.categories,
    required this.loading,
    required this.error,
    required this.page,
    required this.totalCount,
    required this.totalPages,
    required this.pageSize,
    required this.pageSizeOptions,
    required this.paginatorController,
    required this.searchCtrl,
    required this.keyboardTarget,
    required this.selectedCategoryId,
    required this.onSearch,
    required this.onPageChange,
    required this.onPageSizeChange,
    required this.onEdit,
    required this.onNew,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final catName = selectedCategoryId == null
        ? S.current.strAllDishes
        : categories
                  .where((cat) => cat.id == selectedCategoryId)
                  .firstOrNull
                  ?.name ??
              '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Toolbar ──
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      catName,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: c.textDefault,
                        fontFamily: 'Inter',
                        letterSpacing: -0.4,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      totalCount == 0
                          ? 'Taomlar topilmadi'
                          : '$totalCount ta taom',
                      style: TextStyle(
                        fontSize: 13,
                        color: c.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 280,
                child: _SearchField(
                  controller: searchCtrl,
                  keyboardTarget: keyboardTarget,
                  hint: 'Taom qidirish...',
                  onChanged: onSearch,
                ),
              ),
              const SizedBox(width: 12),
              _PrimaryBtn(
                label: S.current.strNewMeal,
                icon: Icons.add_rounded,
                onTap: onNew,
              ),
            ],
          ),
        ),
        // ── Content ──
        Expanded(
          child: loading
              ? const _GoodsSkeleton()
              : error != null
              ? _GoodsErrorState(message: error!, onRetry: onRetry)
              : goods.isEmpty
              ? _GoodsEmptyState(onNew: onNew)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // Grid: 3–7 ustun ekran kengligiga qarab
                    // Compact ekranlarda kichikroq min width (ko'p ustun)
                    final minCardW = PosBreakpoints.pick<double>(
                      context,
                      compact: PosDimensions.gridItemMinWidth, // 160
                      comfortable: PosDimensions.gridItemMinWidthLg, // 200
                    );
                    const gap = PosDimensions.s + 2; // 10
                    final w =
                        constraints.maxWidth - PosDimensions.xxl * 2; // 24+24
                    final cols = (w / (minCardW + gap)).floor().clamp(3, 7);
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        PosDimensions.xxl, // 24
                        0,
                        PosDimensions.xxl,
                        PosDimensions.l, // 16
                      ),
                      itemCount: goods.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        crossAxisSpacing: gap,
                        mainAxisSpacing: gap,
                        childAspectRatio: 0.92,
                      ),
                      itemBuilder: (context, i) {
                        final g = goods[i];
                        final catNameLocal =
                            categories
                                .where((c) => c.id == g.categoryId)
                                .firstOrNull
                                ?.name ??
                            '';
                        return ProductGridCard(
                          good: g,
                          categoryName: catNameLocal,
                          onTap: () => onEdit(g),
                        );
                      },
                    );
                  },
                ),
        ),
        // ── Pagination ──
        if (!loading && error == null)
          _PaginationBar(
            page: page,
            totalPages: totalPages,
            pageSize: pageSize,
            pageSizeOptions: pageSizeOptions,
            paginatorController: paginatorController,
            onPageChange: onPageChange,
            onPageSizeChange: onPageSizeChange,
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// Skeleton / Empty / Error states
// ═══════════════════════════════════════════════════════

class _GoodsSkeleton extends StatelessWidget {
  const _GoodsSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        const minCardW = 160.0;
        const gap = 10.0;
        final w = constraints.maxWidth - 48;
        final cols = (w / (minCardW + gap)).floor().clamp(3, 7);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          itemCount: cols * 3,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            childAspectRatio: 0.92,
          ),
          itemBuilder: (_, _) => Container(
            decoration: BoxDecoration(
              color: c.bgDefault,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.bgSecondary,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(15),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 12,
                        width: 120,
                        decoration: BoxDecoration(
                          color: c.bgSecondary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 14,
                        width: 80,
                        decoration: BoxDecoration(
                          color: c.bgSecondary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GoodsEmptyState extends StatelessWidget {
  final VoidCallback onNew;

  const _GoodsEmptyState({required this.onNew});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: c.textBrand.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.restaurant_menu_outlined,
              size: 32,
              color: c.textBrand,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            "Hozircha taom qo'shilmagan",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: c.textDefault,
              fontFamily: 'Inter',
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Menyuga birinchi taomni qo\'shing',
            style: TextStyle(
              fontSize: 13,
              color: c.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 18),
          _PrimaryBtn(
            label: S.current.strNewMeal,
            icon: Icons.add_rounded,
            onTap: onNew,
          ),
        ],
      ),
    );
  }
}

class _GoodsErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _GoodsErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 36, color: c.systemError),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: c.systemError,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(S.current.strRetry),
          ),
        ],
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  final int page;
  final int totalPages;
  final int pageSize;
  final List<int> pageSizeOptions;
  final NumberPaginatorController paginatorController;
  final void Function(int) onPageChange;
  final void Function(int) onPageSizeChange;

  const _PaginationBar({
    required this.page,
    required this.totalPages,
    required this.pageSize,
    required this.pageSizeOptions,
    required this.paginatorController,
    required this.onPageChange,
    required this.onPageSizeChange,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                secondary: c.buttonBrand,
                onSecondary: c.textOnBrand,
              ),
            ),
            child: SizedBox(
              width: 320,
              // POS minimum touch zone — barmoqqa qulay
              height: 48,
              child: NumberPaginator(
                controller: paginatorController,
                numberPages: totalPages,
                initialPage: (page - 1).clamp(0, totalPages - 1),
                onPageChange: (idx) {
                  if (idx + 1 != page) onPageChange(idx + 1);
                },
                child: const SizedBox(
                  height: 48,
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
          const Spacer(),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.bgSecondary,
              borderRadius: BorderRadius.circular(PosDimensions.radiusMd),
              border: Border.all(color: c.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: pageSize,
                isDense: true,
                icon: Icon(Icons.expand_more_rounded, color: c.textSecondary),
                style: TextStyle(
                  fontSize: 13,
                  color: c.textDefault,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Inter',
                ),
                items: pageSizeOptions
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(S.current.strPageSize(s)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null && v != pageSize) onPageSizeChange(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// Dialogs
// ═══════════════════════════════════════════════════════

class _CategoryDialog extends StatefulWidget {
  final CategoryModel? existing;
  final Future<void> Function(String name)? onCreate;
  final Future<void> Function(String name)? onUpdate;

  const _CategoryDialog({this.existing, this.onCreate, this.onUpdate});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _nameCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await widget.onCreate?.call(name);
      } else {
        await widget.onUpdate?.call(name);
      }
      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isEdit = widget.existing != null;
    return Dialog(
      backgroundColor: c.bgDefault,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEdit ? 'Kategoriyani tahrirlash' : "Kategoriya qo'shish",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.textDefault,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Nomi *',
                style: TextStyle(
                  fontSize: 12,
                  color: c.textTertiary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                style: TextStyle(
                  fontSize: 13,
                  color: c.textDefault,
                  fontFamily: 'Inter',
                ),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: c.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.borderBrand),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Bekor',
                      style: TextStyle(color: c.textSecondary),
                    ),
                  ),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.buttonBrand,
                      foregroundColor: c.textOnBrand,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(isEdit ? 'Saqlash' : "Qo'shish"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Umumiy tasdiqlash dialogi. [onConfirm] null bo'lsa — tugma bosilganda
/// `Navigator.pop(context, true)` qaytaradi.
// ═══════════════════════════════════════════════════════
// Shared micro-widgets
// ═══════════════════════════════════════════════════════

class _SearchField extends StatefulWidget {
  final String hint;
  final void Function(String) onChanged;
  final TextEditingController? controller;
  final ValueNotifier<TextEditingController?>? keyboardTarget;
  final bool large;

  const _SearchField({
    required this.hint,
    required this.onChanged,
    this.controller,
    this.keyboardTarget,
    this.large = false,
  });

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _ctrl;
  late final bool _ownsCtrl;
  String _last = '';

  @override
  void initState() {
    super.initState();
    _ownsCtrl = widget.controller == null;
    _ctrl = widget.controller ?? TextEditingController();
    _last = _ctrl.text;
    // Virtual keyboard `controller.value` ni dasturiy o'zgartiradi —
    // TextField.onChanged buni TUTMAYDI. Shuning uchun listener orqali
    // kuzatamiz (fizik ham, virtual ham klaviatura uchun ishlaydi).
    _ctrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    if (_ownsCtrl) _ctrl.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final cur = _ctrl.text;
    if (cur == _last) return;
    _last = cur;
    widget.onChanged(cur);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fontSize = widget.large ? 16.0 : 13.0;
    final iconSize = widget.large ? 22.0 : 18.0;
    final vPad = widget.large ? 16.0 : 9.0;
    final radius = widget.large ? 12.0 : 8.0;
    return TextField(
      controller: _ctrl,
      onTap: () => widget.keyboardTarget?.value = _ctrl,
      textInputAction: TextInputAction.search,
      keyboardType: TextInputType.text,
      enableInteractiveSelection: true,
      style: TextStyle(
        fontSize: fontSize,
        color: c.textDefault,
        fontFamily: 'Inter',
      ),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: TextStyle(fontSize: fontSize, color: c.textSecondary),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: iconSize,
          color: c.textTertiary,
        ),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: vPad),
        filled: true,
        fillColor: c.bgSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: c.borderBrand),
        ),
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PrimaryBtn({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        // POS minimum touch zone
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: PosDimensions.l),
        decoration: BoxDecoration(
          color: c.buttonBrand,
          borderRadius: BorderRadius.circular(PosDimensions.radiusMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: PosDimensions.s,
          children: [
            Icon(icon, size: 18, color: c.textOnBrand),
            Text(
              label,
              style: TextStyle(
                fontSize: PosTypography.bodyMd, // 15
                fontWeight: FontWeight.w600,
                color: c.textOnBrand,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.size = 16,
  });

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              widget.icon,
              size: widget.size,
              color: _hovered ? widget.color : widget.color.withOpacity(0.7),
            ),
          ),
        ),
      ),
    );
  }
}
