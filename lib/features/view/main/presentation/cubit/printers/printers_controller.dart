import 'package:dartz/dartz.dart';
import 'package:mary_ai_pos/core/error/failure.dart';
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
/// - **Printer sync stays best-effort over [MainRepository].** Printer settings
///   are device-local first (`PrinterConfigStorage`); pushing/deleting them on
///   the backend is fire-and-forget and its failures are swallowed by the
///   caller, exactly as before — that write path is not yet on the outbox and
///   is out of scope here.
class PrintersController {
  final MenuRepository _menu;
  final MainRepository _remote;

  PrintersController({required MenuRepository menu, required MainRepository remote})
      : _menu = menu,
        _remote = remote;

  /// The category catalogue, live from the replica.
  List<CategoryModel> categories() => _menu.getCategories();

  /// Best-effort backend upsert of a printer setting. The device-local store is
  /// authoritative; the caller does not block on this and ignores its result.
  Future<Either<Failure, bool>> pushPrinterSetting(
    Map<String, dynamic> body, {
    String? existingId,
  }) =>
      _remote.pushPrinterSetting(body, existingId: existingId);

  /// Best-effort backend delete of a printer setting.
  Future<Either<Failure, bool>> deletePrinterSetting(String id) =>
      _remote.deletePrinterSetting(id);
}
