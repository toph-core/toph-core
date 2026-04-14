import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mary_ai_pos/core/api/dio_client.dart';
import 'package:mary_ai_pos/core/api/list_api.dart';
import 'package:mary_ai_pos/core/constants/constants.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/theme/tokens/theme_colors.dart';
import 'package:mary_ai_pos/core/utils/app_formatter.dart';
import 'package:mary_ai_pos/core/routes/app_routes.dart';
import 'package:mary_ai_pos/core/widgets/app_scaffold.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/auth/presentation/cubit/bloc/user_bloc.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/data/models/goods/goods_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/main/widgets/main_header.dart';

/// Admin/manager: barcha taomlar ro'yxati — admin web `/menu/meals` ga mos.
class MenuMealsListScreen extends StatefulWidget {
  const MenuMealsListScreen({super.key});

  @override
  State<MenuMealsListScreen> createState() => _MenuMealsListScreenState();
}

class _MenuMealsListScreenState extends State<MenuMealsListScreen> {
  final DioClient _client = inject<DioClient>();
  static const int _pageSize = 20;

  List<GoodsModel> _goods = const [];
  Map<String, String> _categoryNameById = {};
  bool _loading = true;
  String? _error;
  int _page = 1;
  int? _totalCount;
  bool _hasNextPage = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catRes = await _client.get(ListAPI.categories);
      final cats =
          (catRes.data['data'] as List?)
              ?.map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <CategoryModel>[];
      _categoryNameById = {for (final c in cats) c.id: c.name};

      final offset = (page - 1) * _pageSize;
      final goodsRes = await _client.get(
        ListAPI.goods,
        queryParameters: {'limit': _pageSize, 'offset': offset},
      );
      final list = _extractGoodsList(goodsRes.data);
      final total = _extractTotalCount(goodsRes.data);

      if (!mounted) return;
      setState(() {
        _goods = list;
        _page = page;
        _totalCount = total;
        _hasNextPage = total != null
            ? (page * _pageSize) < total
            : list.length >= _pageSize;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.response?.data is Map
            ? e.response!.data['message']?.toString()
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить меню';
      });
    }
  }

  List<GoodsModel> _extractGoodsList(dynamic rawResponse) {
    dynamic source = rawResponse;
    if (source is Map<String, dynamic>) {
      source =
          source['data'] ?? source['items'] ?? source['results'] ?? const [];
    }
    if (source is Map<String, dynamic>) {
      source =
          source['items'] ?? source['results'] ?? source['data'] ?? const [];
    }
    if (source is! List) return const <GoodsModel>[];
    return source
        .whereType<Map>()
        .map((e) => GoodsModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  int? _extractTotalCount(dynamic rawResponse) {
    if (rawResponse is! Map<String, dynamic>) return null;
    final candidates = [
      rawResponse['count'],
      rawResponse['total'],
      rawResponse['meta'] is Map ? (rawResponse['meta'] as Map)['total'] : null,
      rawResponse['meta'] is Map ? (rawResponse['meta'] as Map)['count'] : null,
      rawResponse['pagination'] is Map
          ? (rawResponse['pagination'] as Map)['total']
          : null,
    ];
    for (final c in candidates) {
      if (c is num) return c.toInt();
      if (c is String) {
        final parsed = int.tryParse(c);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  Future<void> _openManage({String? mealId}) async {
    await Navigator.pushNamed(
      context,
      AppRoutes.menuManageScreen,
      arguments: mealId == null ? null : {'meal_id': mealId},
    );
    if (!mounted) return;
    await _load(page: _page);
  }

  @override
  Widget build(BuildContext context) {
    final role = context.select((UserBloc b) => b.state.userMOdel?.role);
    final allowed = role == UserRole.admin || role == UserRole.manager;
    final colors = context.colors;

    return AppScaffold(
      activeRoute: AppRoutes.menuMealsScreen,
      body: Column(
        children: [
          const MainHeader(title: 'Меню'),
          Expanded(
            child: Container(
              color: colors.bgDefault,
              child: !allowed
                  ? Center(
                      child: Text(
                        'Доступ только для администратора и менеджера',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    )
                  : _loading
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : _body(colors),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(ThemeColors colors) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: TextStyle(color: colors.systemError)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _load(page: _page),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_goods.isEmpty) {
      return Center(
        child: Text(
          'Нет позиций',
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    }

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                'Все блюда (${_totalCount ?? _goods.length})',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textDefault,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _goods.length,
                separatorBuilder: (_, i) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final g = _goods[i];
                  final catName =
                      _categoryNameById[g.categoryId] ?? g.categoryId;
                  return Material(
                    color: colors.bgSecondary,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _openManage(mealId: g.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    g.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textDefault,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    catName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              AppFormatter.formatAmountWithSpaces(g.price),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.textBrand,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: colors.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Text(
                    'Page $_page',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _loading || _page <= 1
                        ? null
                        : () => _load(page: _page - 1),
                    child: const Text('Prev'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _loading || !_hasNextPage
                        ? null
                        : () => _load(page: _page + 1),
                    child: const Text('Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingActionButton.extended(
            onPressed: () => _openManage(),
            icon: const Icon(Icons.add),
            label: const Text('Новое блюдо'),
            backgroundColor: colors.buttonBrand,
            foregroundColor: colors.textOnBrand,
          ),
        ),
      ],
    );
  }
}
