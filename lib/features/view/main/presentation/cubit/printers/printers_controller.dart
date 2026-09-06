import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
import 'package:mary_ai_pos/core/service/printer/printer_setting_entry.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_repository.dart';

/// OFFLINE_FIRST_EVERYWHERE_PLAN.md §7 — the printer-settings section reads
/// through this instead of resolving repositories itself, so the widget layer
/// stops reaching into DI (the §9.2 guard) and the data source is a seam that
/// can move without touching the screen.
///
/// Two sources, on purpose:
/// - **Categories from the replica.** Printer→category assignment only needs
///   the catalogue for display and selection; it is replicated, so this reads
///   [MenuRepository] (a synchronous `LocalDatabase` query) rather than the old
///   cache-then-best-effort-network dance. Always available, offline, no
///   empty-then-populate flash.
/// - **Printer writes go to the backend over [MainRepository].** Printer
///   settings are device-local first (`PrinterConfigStorage`), but the push is
///   no longer fire-and-forget: the settings screen waits for it, adopts the id
///   the server assigns, and tells the operator when the entry stayed local.
///   That write path is still not on the outbox (see `write_path_guard_test`),
///   so offline it fails — visibly now, instead of silently.
class PrintersController {
  final MenuRepository _menu;
  final MainRepository _remote;

  PrintersController({required MenuRepository menu, required MainRepository remote})
      : _menu = menu,
        _remote = remote;

  /// The category catalogue, live from the replica.
  List<CategoryModel> categories() => _menu.getCategories();

  /// Backend upsert of a printer setting. The device-local store is
  /// authoritative, but the caller waits for this and acts on the result: the
  /// returned record's id replaces the local one, and a failure is shown to the
  /// operator rather than swallowed.
  Future<Either<Failure, PrinterSettingEntry?>> pushPrinterSetting(
    Map<String, dynamic> body, {
    String? existingId,
  }) =>
      _remote.pushPrinterSetting(body, existingId: existingId);

  /// Best-effort backend delete of a printer setting.
  Future<Either<Failure, bool>> deletePrinterSetting(String id) =>
      _remote.deletePrinterSetting(id);
}
