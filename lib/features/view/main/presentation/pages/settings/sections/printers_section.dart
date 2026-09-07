import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/widgets/styled_virtual_keyboard.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config_storage.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/service/printer/printer_setting_entry.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/presentation/cubit/printers/printers_controller.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/settings/widgets/section_shell.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class PrintersSection extends StatefulWidget {
  const PrintersSection({super.key});

  @override
  State<PrintersSection> createState() => _PrintersSectionState();
}

class _PrintersSectionState extends State<PrintersSection> {
  final PrintersController _printers = inject<PrintersController>();
  final PrinterConfigStorage _storage = inject<PrinterConfigStorage>();

  bool _loading = true;
  List<PrinterSettingEntry> _items = const [];
  List<CategoryModel> _categories = const [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  /// Printer ro'yxati **shu qurilmadagi** lokal saqlashdan; kategoriya nomlari
  /// esa replikadan (o'zgarish tasmasi to'ldiradi) — sinxron, oflayn, tarmoq
  /// so'rovisiz va "avval bo'sh, keyin to'ladi" miltillashisiz.
  void _loadAll() {
    setState(() {
      _items = _storage.listEntries();
      _categories = _printers.categories();
      _loading = false;
    });
  }

  /// Bu yozuvni qo'shni terminal LAN orqali e'lon qilgan — u yerdagi
  /// printer, shu qurilmada faqat marshrutlash uchun ko'rinadi.
  bool _isPeerEntry(PrinterSettingEntry e) => _storage.isLanLearned(e.id);

  static const _peerEntryNotice =
      'Bu printer boshqa terminalga ulangan — uni o\'sha terminalning '
      'sozlamalaridan o\'zgartiring. Cheklar bu yerdan LAN orqali avtomatik '
      'yuboriladi.';

  Future<void> _openEditor({PrinterSettingEntry? existing}) async {
    // A peer's row is peer knowledge, not this terminal's to edit: saving it
    // here would push another terminal's printer to the backend under this
    // terminal's hand, and the peer's next announcement would overwrite it
    // anyway.
    if (existing != null && _isPeerEntry(existing)) {
      showErrorMessage(context, _peerEntryNotice);
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PrinterEditDialog(
        existing: existing,
        categories: _categories,
        controller: _printers,
        storage: _storage,
      ),
    );
    if (saved == true && mounted) {
      _loadAll();
      // Tell the other terminals what changed here, so a job for this printer
      // is relayed to this machine rather than dialled from theirs.
      inject<PrinterSettingsAnnouncer>()();
    }
  }

  Future<void> _confirmDelete(PrinterSettingEntry item) async {
    if (_isPeerEntry(item)) {
      showErrorMessage(context, _peerEntryNotice);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDeleteDialog(
        title: S.current.strDeletePrinter,
        message:
            '${item.ip}:${item.port} printerini o\'chirmoqchimisiz? Buni bekor qilib bo\'lmaydi.',
      ),
    );
    if (ok != true || !mounted) return;
    // Lokal — har doim ishlaydi. Backend — eng yaxshi urinish, muvaffaqiyatsiz
    // bo'lsa ham lokal o'chirish kuchda qoladi (faqat sinov uchun jim log).
    await _storage.deleteEntry(item.id);
    // `local-…` — backend bu yozuvni hech qachon ko'rmagan (uni `uuid.Parse`
    // da rad etadi), so'rov yuborishning ma'nosi yo'q.
    if (!PrinterConfigStorage.isLocalId(item.id)) {
      unawaited(
        _printers.deletePrinterSetting(item.id).then((result) {
          result.fold(
            (f) => debugPrint('[PrintersSection] Backend delete xatosi (e\'tiborsiz): $f'),
            (_) {},
          );
        }),
      );
    }
    if (!mounted) return;
    inject<PrinterConfigStorage>().removeUsbPrinterName(item.id);
    inject<PrinterConfigStorage>().removePaperSize(item.id);
    _loadAll();
    inject<PrinterSettingsAnnouncer>()();
  }

  String _categoryName(String id) {
    final c = _categories.firstWhere(
      (x) => x.id == id,
      orElse: () => const CategoryModel(id: '', name: ''),
    );
    return c.name.isNotEmpty ? c.name : id;
  }

  @override
  Widget build(BuildContext context) {
    return SectionShell(
      title: S.current.strPrinterSettings,
      subtitle:
          '${_items.length} ta ESC/POS qurilma — kategoriya va chek printerlari',
      trailing: SectionPrimaryButton(
        icon: Icons.add_rounded,
        label: S.current.strAddPrinter,
        onPressed: () => _openEditor(),
      ),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_items.isEmpty) {
      return SectionEmptyState(
        icon: Icons.print_outlined,
        title: S.current.strNoPrintersYet,
        subtitle:
            'Kategoriyalar va yopiq cheklar uchun ESC/POS TCP printerlarni shu yerdan qo\'shing.',
        action: SectionPrimaryButton(
          icon: Icons.add_rounded,
          label: S.current.strAddFirstPrinter,
          onPressed: () => _openEditor(),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _PrinterCard(
        entry: _items[i],
        categoryNameFor: _categoryName,
        onEdit: () => _openEditor(existing: _items[i]),
        onDelete: () => _confirmDelete(_items[i]),
      ),
    );
  }
}

class _PrinterCard extends StatefulWidget {
  final PrinterSettingEntry entry;
  final String Function(String id) categoryNameFor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PrinterCard({
    required this.entry,
    required this.categoryNameFor,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_PrinterCard> createState() => _PrinterCardState();
}

class _PrinterCardState extends State<_PrinterCard> {
  bool _hover = false;
  bool _testing = false;

  Future<void> _testPrint() async {
    if (_testing) return;
    final entry = widget.entry;

    // Test print is a direct connection, not a queued job, so it cannot go
    // through the LAN relay the way a real receipt does. Against a printer
    // registered to another terminal it would simply sit out its socket
    // timeout and report a failure that says nothing useful — better to say
    // where the test has to be run from.
    final storage = inject<PrinterConfigStorage>();
    if (storage.isLanLearned(entry.id) ||
        (!entry.isUnowned && !storage.isOwnedByThisTerminal(entry))) {
      showErrorMessage(
        context,
        'Bu printer boshqa terminalga biriktirilgan — testni o\'sha '
        'terminaldan bajaring. Haqiqiy cheklar LAN orqali avtomatik '
        'yuboriladi.',
      );
      return;
    }

    final isUsb = entry.connectionType == 'usb';
    String? windowsPrinterName;
    if (isUsb) {
      windowsPrinterName =
          inject<PrinterConfigStorage>().getUsbPrinterName(entry.id);
      if (windowsPrinterName == null || windowsPrinterName.isEmpty) {
        showErrorMessage(
          context,
          'Bu USB printer uchun ushbu kompyuterda printer tanlanmagan — '
          'Tahrirlashda tanlang',
        );
        return;
      }
    }
    setState(() => _testing = true);
    final result = await inject<PrinterService>().testPrint(
      ip: entry.ip,
      port: entry.port,
      connectionType: entry.connectionType,
      windowsPrinterName: windowsPrinterName,
      paperSize: inject<PrinterConfigStorage>().getPaperSize(entry.id),
    );
    if (!mounted) return;
    setState(() => _testing = false);
    if (result.ok) {
      showSuccessMessage(
        context,
        isUsb
            ? 'Test cheki "$windowsPrinterName" ga yuborildi'
            : 'Test cheki ${entry.ip}:${entry.port} ga yuborildi',
      );
    } else {
      showErrorMessage(
        context,
        result.error ?? 'Printerga ulanib bo\'lmadi',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entry = widget.entry;
    final isCloseCheck = entry.isCloseCheck;
    final typeColor = isCloseCheck ? colors.extraOrange : colors.systemAccent;
    final connectionIcon = switch (entry.connectionType) {
      'wlan' => Icons.wifi_rounded,
      'usb' => Icons.usb_rounded,
      _ => Icons.cable_rounded,
    };
    final connLabel = switch (entry.connectionType) {
      'wlan' => S.current.strWiFi,
      'usb' => 'USB',
      _ => S.current.strCable,
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: colors.bgDefault,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hover ? colors.buttonBrand : colors.border,
            width: _hover ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.print_rounded, color: typeColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _title(entry),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: colors.textDefault,
                            fontFamily: 'Inter',
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _Badge(
                        color: typeColor,
                        label: isCloseCheck ? S.current.strCheckPrinter : S.current.strCategory,
                      ),
                      // A printer the neighbouring terminal announced over the
                      // LAN. Shown, because the operator needs to know the
                      // venue has it — but it is that terminal's to change.
                      if (inject<PrinterConfigStorage>().isLanLearned(entry.id)) ...[
                        const SizedBox(width: 6),
                        _Badge(
                          color: colors.textSecondary,
                          label: 'Boshqa terminal',
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(connectionIcon,
                          size: 13, color: colors.textSecondary),
                      const SizedBox(width: 5),
                      Text(
                        connLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      _Dot(color: colors.border),
                      Icon(
                        _ownedHere ? Icons.desktop_windows_rounded : Icons.lan_rounded,
                        size: 13,
                        color: _ownedHere ? colors.systemAccent : colors.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _ownerLabel(entry),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _ownedHere
                              ? colors.systemAccent
                              : colors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      if (entry.isCategory) ...[
                        _Dot(color: colors.border),
                        Flexible(
                          child: Text(
                            _categoriesLabel(entry),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colors.textSecondary,
                              fontFamily: 'Inter',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Row(
              children: [
                _testing
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _GhostIconButton(
                        icon: Icons.print_outlined,
                        tooltip: 'Test printer',
                        color: colors.systemAccent,
                        onTap: _testPrint,
                      ),
                const SizedBox(width: 8),
                _GhostIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: S.current.strEdit,
                  color: colors.buttonBrand,
                  onTap: widget.onEdit,
                ),
                const SizedBox(width: 8),
                _GhostIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: S.current.strDelete,
                  color: colors.systemError,
                  onTap: widget.onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Whether this terminal is the printer's registered owner — the printers it
  /// drives directly. Everything else either belongs to a sibling terminal (a
  /// job for it is relayed over the LAN hub) or to nobody.
  bool get _ownedHere =>
      inject<PrinterConfigStorage>().isOwnedByThisTerminal(widget.entry);

  /// A USB printer has no address to show, so the operator-supplied name is the
  /// only thing that identifies it. Network printers fall back to `ip:port`,
  /// which is what this card always used to show.
  String _title(PrinterSettingEntry entry) {
    if (entry.name.isNotEmpty) return entry.name;
    if (entry.isAddressless) return 'USB printer';
    return '${entry.ip}:${entry.port}';
  }

  String _ownerLabel(PrinterSettingEntry entry) {
    if (entry.isUnowned) return 'Har qanday terminal';
    return _ownedHere ? 'Shu terminal' : 'Boshqa terminal';
  }

  String _categoriesLabel(PrinterSettingEntry entry) {
    if (entry.connectedEntityIds.isEmpty) {
      return 'Kategoriyalar tanlanmagan';
    }
    final names =
        entry.connectedEntityIds.take(3).map(widget.categoryNameFor).join(', ');
    final more = entry.connectedEntityIds.length > 3
        ? ' +${entry.connectedEntityIds.length - 3}'
        : '';
    return '$names$more';
  }
}

class _Badge extends StatelessWidget {
  final Color color;
  final String label;
  const _Badge({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          fontFamily: 'Inter',
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _GhostIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;

  const _GhostIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  State<_GhostIconButton> createState() => _GhostIconButtonState();
}

class _GhostIconButtonState extends State<_GhostIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconColor = widget.color ?? colors.buttonBrand;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: iconColor.withOpacity(_hover ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(widget.icon, size: 22, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmDeleteDialog extends StatelessWidget {
  final String title;
  final String message;
  const _ConfirmDeleteDialog({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.systemError.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.warning_amber_rounded,
                        color: colors.systemError, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.textDefault,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _DialogButton.ghost(
                    label: S.current.strCancel,
                    onPressed: () => Navigator.pop(context, false),
                  ),
                  const SizedBox(width: 8),
                  _DialogButton.danger(
                    label: S.current.strDelete,
                    onPressed: () => Navigator.pop(context, true),
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

class _DialogButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final _ButtonKind kind;

  const _DialogButton._(this.kind,
      {required this.label, required this.onPressed});

  factory _DialogButton.ghost(
          {required String label, required VoidCallback? onPressed}) =>
      _DialogButton._(_ButtonKind.ghost, label: label, onPressed: onPressed);

  factory _DialogButton.danger(
          {required String label, required VoidCallback? onPressed}) =>
      _DialogButton._(_ButtonKind.danger, label: label, onPressed: onPressed);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    late final Color bg;
    late final Color fg;
    late final BorderSide border;
    switch (kind) {
      case _ButtonKind.ghost:
        bg = Colors.transparent;
        fg = colors.textSecondary;
        border = BorderSide(color: colors.border);
        break;
      case _ButtonKind.danger:
        bg = colors.systemError;
        fg = Colors.white;
        border = BorderSide.none;
        break;
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.fromBorderSide(border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
              fontFamily: 'Inter',
            ),
          ),
        ),
      ),
    );
  }
}

enum _ButtonKind { ghost, danger }

class _PrinterEditDialog extends StatefulWidget {
  final PrinterSettingEntry? existing;
  final List<CategoryModel> categories;
  final PrintersController controller;
  final PrinterConfigStorage storage;

  const _PrinterEditDialog({
    required this.existing,
    required this.categories,
    required this.controller,
    required this.storage,
  });

  @override
  State<_PrinterEditDialog> createState() => _PrinterEditDialogState();
}

class _PrinterEditDialogState extends State<_PrinterEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ipCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _nameCtrl;
  String _type = 'category';
  String _connection = 'cable';

  /// Whether this printer is registered to *this* terminal. Defaults to true
  /// for a new printer, and deliberately so: the overwhelmingly common case is
  /// an operator adding the printer that is plugged into, or on the same
  /// switch as, the machine they are standing at. Leaving it unowned by default
  /// would preserve the old "every terminal can reach every printer"
  /// assumption, which is the failure this whole feature exists to remove.
  bool _ownedByThisTerminal = true;
  // Chek kengligi — XPRINTER_SETUP.md: ba'zi "80mm" printerlar 32 belgi (58mm)
  // chiqaradi, boshqalari 48 (80mm). Shu qurilmada `entryId` bo'yicha saqlanadi.
  String _paperSizeCode = kPaperSizeCode80;
  final Set<String> _selectedCategoryIds = {};
  bool _saving = false;
  String? _saveError;

  /// Shu dialogda yaratilgan yozuvning lokal id'si — faqat yangi printer
  /// uchun va faqat backendga yetkazilgunicha.
  String? _localEntryId;

  /// Lokal saqlandi, lekin backendga yuborib bo'lmadi — operatorga aytiladigan
  /// ogohlantirish. `null` bo'lmasa dialog yopilmagan holda turadi: o'sha
  /// Saqlash tugmasi qayta urinish uchun qoladi, yopish esa ro'yxatni
  /// yangilaydi (yozuv lokal saqlangan, uni ko'rsatish kerak).
  String? _localOnlyWarning;
  bool _testing = false;
  bool? _testOk; // null = no test run yet
  String? _testMessage;

  // USB (Windows spooler) — bu qurilmada o'rnatilgan printerlar ro'yxati va
  // tanlangan nom. Backend bilan sinxronlanmaydi (PrinterConfigStorage,
  // faqat shu qurilmada).
  String? _windowsPrinterName;
  List<String> _localPrinters = const [];
  bool _loadingLocalPrinters = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _ipCtrl = TextEditingController(text: e?.ip ?? '');
    _portCtrl = TextEditingController(
      text: (e == null || e.port <= 0 ? 9100 : e.port).toString(),
    );
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    if (e != null) {
      _type = e.type.isNotEmpty ? e.type : 'category';
      _connection = e.connectionType.isNotEmpty ? e.connectionType : 'cable';
      // An existing printer keeps whatever it has: owned here, owned by a
      // sibling terminal, or unowned. Editing must never silently re-home a
      // printer onto whichever terminal happened to open the dialog.
      _ownedByThisTerminal = widget.storage.isOwnedByThisTerminal(e);
      _paperSizeCode =
          inject<PrinterConfigStorage>().getPaperSizeCode(e.id) ??
              kPaperSizeCode80;
      _selectedCategoryIds.addAll(e.connectedEntityIds);
      if (_connection == 'usb') {
        _windowsPrinterName =
            inject<PrinterConfigStorage>().getUsbPrinterName(e.id);
      }
    }
    if (Platform.isWindows) _loadLocalPrinters();
  }

  Future<void> _loadLocalPrinters() async {
    setState(() => _loadingLocalPrinters = true);
    // EnumPrinters — sinxron Win32 chaqiruv; bir frame kutib, loading holati
    // ko'rinishi uchun mikrotaskka o'tkazamiz.
    final names =
        await Future(() => inject<PrinterService>().listLocalWindowsPrinterNames());
    if (!mounted) return;
    setState(() {
      _localPrinters = names;
      _loadingLocalPrinters = false;
      // Avval saqlangan tanlov hozir ro'yxatda yo'q bo'lsa ham saqlab
      // qolamiz — printer vaqtincha uzilgan bo'lishi mumkin, tanlovni
      // yo'qotib qo'ymaslik kerak.
    });
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  /// The `cash_register_id` to store as this printer's owner: this terminal's
  /// own when the operator marked it local, `''` (unowned — any terminal prints
  /// to it directly) otherwise.
  ///
  /// Editing a printer that belongs to a *different* terminal keeps that
  /// terminal's id rather than clearing it, so opening someone else's printer
  /// to fix its category list cannot accidentally un-home it.
  String _resolvedOwnerId() {
    if (_ownedByThisTerminal) return widget.storage.myCashRegisterId;
    final existingOwner = widget.existing?.ownerCashRegisterId ?? '';
    if (existingOwner.isNotEmpty &&
        !widget.storage.isOwnedByThisTerminal(widget.existing!)) {
      return existingOwner;
    }
    return '';
  }

  /// Whether the printer being edited belongs to another terminal — the one
  /// case where the ownership toggle is shown read-only, since this screen
  /// cannot know that terminal's hardware.
  bool get _ownedElsewhere {
    final e = widget.existing;
    if (e == null || e.isUnowned) return false;
    return !widget.storage.isOwnedByThisTerminal(e);
  }

  String? _validateName(String? v) {
    final name = v?.trim() ?? '';
    // Required only where it is load-bearing: a USB printer has no address, so
    // the name is the only thing separating two of them on one terminal — and
    // the backend's uniqueness key includes it.
    if (_connection == 'usb' && name.isEmpty) {
      return 'USB printer uchun nom kerak';
    }
    if (name.length > 64) return 'Nom 64 belgidan oshmasin';
    return null;
  }

  String? _validateIp(String? v) {
    if (_connection == 'usb') return null; // USB — IP shart emas
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'IP manzil kerak';
    final parts = s.split('.');
    if (parts.length != 4) return 'IPv4 noto\'g\'ri (192.168.1.100)';
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return 'IPv4 noto\'g\'ri';
    }
    return null;
  }

  String? _validatePort(String? v) {
    if (_connection == 'usb') return null; // USB — port shart emas
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Port kerak';
    final n = int.tryParse(s);
    if (n == null || n <= 0 || n > 65535) return 'Port 1–65535 oraliqda';
    return null;
  }

  /// Lokal saqlash — har doim ishlaydi, birlamchi manba. Undan keyin yozuv
  /// backendga yuboriladi va **javobi kutiladi** ([_pushToBackend]):
  ///
  ///  * yuborildi — dialog yopiladi, yozuv backend id'siga o'tkaziladi;
  ///  * yuborilmadi — lokal saqlangani kuchda qoladi, lekin dialog yopilmaydi:
  ///    operator printer faqat shu terminalda turganini ko'radi va tarmoq
  ///    tiklanganda Saqlashni qayta bosa oladi. Ilgari bu holat jim
  ///    `debugPrint` bo'lib ketardi — printer qo'shildi ko'rinardi-yu,
  ///    qo'shni terminal uni umuman bilmasdi, tizimdan chiqilganda esa yo'q
  ///    bo'lardi.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_type == 'category' && _selectedCategoryIds.isEmpty) {
      setState(() => _saveError = 'Kamida bitta kategoriya tanlang');
      return;
    }
    if (_connection == 'usb' &&
        (_windowsPrinterName == null || _windowsPrinterName!.isEmpty)) {
      setState(() => _saveError = 'USB printer tanlang');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
      _localOnlyWarning = null;
    });

    // USB has no address. It used to be given a placeholder `127.0.0.1:9100`
    // to satisfy the backend's ip/port validation, which had the side effect of
    // collapsing every USB printer in the brand onto one uniqueness key —
    // `(ip, port, type)` left `type`'s two values as the only discriminator, so
    // a brand could store exactly two USB printers in total. The API stopped
    // requiring an address for `usb` in 75_printer_settings_owner; sending a
    // blank one is now both honest and what keeps them distinct.
    final isUsb = _connection == 'usb';
    final ip = isUsb ? '' : _ipCtrl.text.trim();
    final port = isUsb ? 0 : int.parse(_portCtrl.text.trim());
    // Bitta lokal id — «Qayta urinish» bosilganda yangisi yaratilmaydi,
    // aks holda har urinish ro'yxatga yana bitta nusxa qo'shardi.
    final entryId =
        widget.existing?.id ?? _localEntryId ?? widget.storage.generateLocalId();
    _localEntryId = entryId;
    final entry = PrinterSettingEntry(
      id: entryId,
      ip: ip,
      port: port,
      name: _nameCtrl.text.trim(),
      type: _type,
      connectedEntityIds:
          _type == 'category' ? _selectedCategoryIds.toList() : <String>[],
      connectionType: _connection,
      branchId: widget.existing?.branchId ?? '',
      ownerCashRegisterId: _resolvedOwnerId(),
    );

    await widget.storage.upsertEntry(entry);

    // Chek kengligi — shu qurilmada, `entryId` bo'yicha (backend saqlamaydi).
    await widget.storage.savePaperSizeCode(entryId, _paperSizeCode);

    final cache = inject<PrinterConfigStorage>();
    if (isUsb && _windowsPrinterName != null) {
      await cache.saveUsbPrinterName(entryId, _windowsPrinterName!);
    } else {
      // Turi 'usb'dan boshqasiga o'zgargan bo'lishi mumkin — eski lokal
      // tanlovni qoldirmaymiz.
      await cache.removeUsbPrinterName(entryId);
    }

    final pushed = await _pushToBackend(entry);

    if (!mounted) return;
    if (!pushed) {
      setState(() {
        _saving = false;
        _localOnlyWarning =
            'Printer faqat shu terminalda saqlandi — serverga yuborib '
            'bo\'lmadi. Boshqa terminallar uni ko\'rmaydi, tizimdan '
            'chiqsangiz esa yo\'qoladi. Aloqa tiklangach shu oynada yana '
            'saqlang.';
      });
      return;
    }
    Navigator.pop(context, true);
  }

  /// Backendga yozadi. Muvaffaqiyatli bo'lsa `true`, va yozuv backend bergan
  /// `id` ga o'tkaziladi ([PrinterConfigStorage.adoptBackendId]) — shu
  /// qurilmadagi USB nomi va chek kengligi u bilan birga ko'chadi.
  ///
  /// Ilgari lokal `local-…` id qasddan qoldirilar edi. Natijada bir printer
  /// ikki terminalda ikki xil id ostida turar, keyingi tahrir esa
  /// `PUT /…/local-…` bo'lib backend tomonidan rad etilardi (u id ni
  /// `uuid.Parse` qiladi) — ya'ni yozuv o'zini hech qachon tuzata olmasdi.
  Future<bool> _pushToBackend(PrinterSettingEntry entry) async {
    final body = {
      'ip': entry.ip,
      'port': entry.port,
      'name': entry.name,
      'type': entry.type,
      'connection_type': entry.connectionType,
      // Always sent, never omitted. The API reads an *absent*
      // `owner_cash_register_id` as "the calling terminal" and an explicit `""`
      // as "unowned"; this screen always knows which of the two the operator
      // picked, so it says so rather than leaning on the default.
      'owner_cash_register_id': entry.ownerCashRegisterId,
      'connected_entity_ids': entry.connectedEntityIds,
    };
    final result = await widget.controller.pushPrinterSetting(
      body,
      // `local-…` bo'lsa data-source uni yaratish (`POST`) sifatida yuboradi.
      existingId: widget.existing?.id,
    );
    PrinterSettingEntry? saved;
    var ok = true;
    result.fold(
      (f) {
        debugPrint('[PrinterEditDialog] Backend yozish xatosi: $f');
        ok = false;
      },
      // `null` — server qabul qildi, lekin javobida yozuv yo'q: id ni
      // almashtirmaymiz, ammo bu muvaffaqiyat.
      (record) => saved = record,
    );
    if (!ok) return false;

    final backendId = saved?.id ?? '';
    if (backendId.isNotEmpty && backendId != entry.id) {
      await widget.storage.adoptBackendId(
        localId: entry.id,
        backendId: backendId,
        branchId: (saved?.branchId ?? '').isNotEmpty ? saved!.branchId : null,
      );
    }
    debugPrint('[PrinterEditDialog] Backendga yozildi: $backendId');
    return true;
  }

  /// IP/port/ulanish turini — hozir formaga kiritilgan qiymatlarni, saqlash
  /// shart bo'lmasdan — to'g'ridan-to'g'ri shu printerga chek yuborib sinaydi.
  /// Kategoriya tanlovi yoki boshqa Save-only qoidalar bu yerda talab qilinmaydi.
  Future<void> _testPrinter() async {
    if (_connection == 'usb') {
      if (_windowsPrinterName == null || _windowsPrinterName!.isEmpty) {
        setState(() {
          _testOk = false;
          _testMessage = 'Avval USB printerni tanlang';
        });
        return;
      }
    } else {
      final ipError = _validateIp(_ipCtrl.text);
      final portError = _validatePort(_portCtrl.text);
      if (ipError != null || portError != null) {
        setState(() {
          _testOk = false;
          _testMessage = ipError ?? portError;
        });
        return;
      }
    }
    setState(() {
      _testing = true;
      _testOk = null;
      _testMessage = null;
    });
    final result = await inject<PrinterService>().testPrint(
      ip: _connection == 'usb' ? '' : _ipCtrl.text.trim(),
      port: _connection == 'usb' ? 0 : int.parse(_portCtrl.text.trim()),
      connectionType: _connection,
      windowsPrinterName: _connection == 'usb' ? _windowsPrinterName : null,
      paperSize: paperSizeFromCode(_paperSizeCode),
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = result.ok;
      _testMessage = result.ok
          ? 'Test cheki yuborildi — printerni tekshiring.'
          : (result.error ?? 'Printerga ulanib bo\'lmadi');
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isEdit = widget.existing != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeader(
              icon: isEdit ? Icons.edit_outlined : Icons.add_rounded,
              title: isEdit ? S.current.strEditPrinter : S.current.strAddPrinter,
              subtitle: isEdit
                  ? 'Printer sozlamalarini o\'zgartiring'
                  : 'Yangi ESC/POS TCP printerni qo\'shing',
              onClose: () => Navigator.pop(context, _localOnlyWarning != null),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LabeledField(
                        label: 'Nom',
                        helper: _connection == 'usb'
                            ? 'USB printerda manzil yo\'q — ro\'yxatda uni shu '
                                'nom ajratib turadi («Oshxona», «Bar»)'
                            : 'Ixtiyoriy — ro\'yxatda IP o\'rniga ko\'rinadi',
                        child: _TextField(
                          controller: _nameCtrl,
                          hint: 'Oshxona',
                          validator: _validateName,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_connection == 'usb') ...[
                        _LabeledField(
                          label: 'USB printer',
                          helper: _loadingLocalPrinters
                              ? null
                              : 'Ushbu kompyuterda o\'rnatilgan printer — Windows '
                                  'qaysi biriga chop etishni shu nom orqali biladi',
                          child: _UsbPrinterPicker(
                            loading: _loadingLocalPrinters,
                            options: _localPrinters,
                            value: _windowsPrinterName,
                            onChanged: (v) =>
                                setState(() => _windowsPrinterName = v),
                            onRefresh: _loadLocalPrinters,
                          ),
                        ),
                      ] else
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _LabeledField(
                                label: S.current.strIPAddress,
                                child: _TextField(
                                  controller: _ipCtrl,
                                  hint: '192.168.1.100',
                                  validator: _validateIp,
                                  formatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9.]')),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: _LabeledField(
                                label: S.current.strPort,
                                child: _TextField(
                                  controller: _portCtrl,
                                  hint: '9100',
                                  keyboard: TextInputType.number,
                                  validator: _validatePort,
                                  formatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 14),
                      _LabeledField(
                        label: S.current.strPrinterType,
                        child: _SegmentedChoice<String>(
                          value: _type,
                          onChanged: (v) => setState(() => _type = v),
                          options: [
                            _ChoiceOption(
                              value: 'category',
                              label: S.current.strCategory,
                              icon: Icons.restaurant_menu_rounded,
                              helper: 'Taomlar uchun',
                            ),
                            _ChoiceOption(
                              value: 'close_check',
                              label: S.current.strCheckPrinter,
                              icon: Icons.receipt_long_rounded,
                              helper: 'Yopish uchun',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _LabeledField(
                        label: S.current.strConnectionType,
                        child: _SegmentedChoice<String>(
                          value: _connection,
                          onChanged: (v) => setState(() => _connection = v),
                          options: [
                            _ChoiceOption(
                              value: 'cable',
                              label: S.current.strCable,
                              icon: Icons.cable_rounded,
                              helper: 'LAN',
                            ),
                            _ChoiceOption(
                              value: 'wlan',
                              label: S.current.strWiFi,
                              icon: Icons.wifi_rounded,
                              helper: 'WLAN',
                            ),
                            // Faqat Windows'da — Windows spooler orqali (bu
                            // qurilmaga to'g'ridan-to'g'ri USB kabel bilan
                            // ulangan printer, IP'siz).
                            if (Platform.isWindows)
                              const _ChoiceOption(
                                value: 'usb',
                                label: 'USB',
                                icon: Icons.usb_rounded,
                                helper: 'To\'g\'ridan',
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _LabeledField(
                        label: 'Qaysi terminalga biriktirilgan',
                        helper: _ownedElsewhere
                            ? 'Bu printer boshqa terminalga biriktirilgan — '
                                'cheklar LAN orqali o\'sha terminalga yuboriladi'
                            : 'Printer faqat bitta kompyuterdan ko\'rinsa — USB '
                                'kabel, oshxona kommutatori, boshqa Wi-Fi nuqtasi — '
                                '«Shu terminal»ni tanlang: boshqa terminallar '
                                'cheklarni LAN orqali shu yerga yuboradi. '
                                '«Har qanday terminal» esa har bir kassa printerga '
                                'o\'zi ulanadi.',
                        child: _ownedElsewhere
                            ? _ReadOnlyOwnerNotice(
                                label: widget.existing?.name.isNotEmpty == true
                                    ? '${widget.existing!.name} — boshqa terminal'
                                    : 'Boshqa terminal',
                              )
                            : _SegmentedChoice<bool>(
                                value: _ownedByThisTerminal,
                                onChanged: (v) =>
                                    setState(() => _ownedByThisTerminal = v),
                                options: const [
                                  _ChoiceOption(
                                    value: true,
                                    label: 'Shu terminal',
                                    icon: Icons.desktop_windows_rounded,
                                    helper: 'Faqat shu yerdan',
                                  ),
                                  _ChoiceOption(
                                    value: false,
                                    label: 'Har qanday terminal',
                                    icon: Icons.lan_rounded,
                                    helper: 'Hammadan ko\'rinadi',
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 14),
                      _LabeledField(
                        label: 'Chek kengligi',
                        helper: 'Ba\'zi "80mm" printerlar 32 belgi (58mm) '
                            'chiqaradi — chek matni buzilsa 58mm ni tanlang',
                        child: _SegmentedChoice<String>(
                          value: _paperSizeCode,
                          onChanged: (v) =>
                              setState(() => _paperSizeCode = v),
                          options: const [
                            _ChoiceOption(
                              value: kPaperSizeCode80,
                              label: '80 mm',
                              icon: Icons.receipt_long_rounded,
                              helper: '48 belgi',
                            ),
                            _ChoiceOption(
                              value: kPaperSizeCode58,
                              label: '58 mm',
                              icon: Icons.receipt_rounded,
                              helper: '32 belgi',
                            ),
                          ],
                        ),
                      ),
                      if (_testMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (_testOk == true
                                    ? colors.systemSuccess
                                    : colors.systemError)
                                .withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _testOk == true
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline,
                                size: 16,
                                color: _testOk == true
                                    ? colors.systemSuccess
                                    : colors.systemError,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _testMessage!,
                                  style: TextStyle(
                                    color: _testOk == true
                                        ? colors.systemSuccess
                                        : colors.systemError,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_type == 'category') ...[
                        const SizedBox(height: 14),
                        _LabeledField(
                          label: S.current.strConnectedCategories,
                          helper:
                              'Shu kategoriyalar uchun buyurtmalar shu printerga yuboriladi',
                          child: _CategoryMultiSelect(
                            categories: widget.categories,
                            selected: _selectedCategoryIds,
                            onChanged: (id, selected) {
                              setState(() {
                                if (selected) {
                                  _selectedCategoryIds.add(id);
                                } else {
                                  _selectedCategoryIds.remove(id);
                                }
                              });
                            },
                          ),
                        ),
                      ],
                      // Lokal saqlandi, serverga yetmadi — xato emas, lekin
                      // jim ham qoldirilmaydi: printer shu terminaldan
                      // tashqarida yo'q.
                      if (_localOnlyWarning != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.systemAccent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  size: 16, color: colors.systemAccent),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _localOnlyWarning!,
                                  style: TextStyle(
                                    color: colors.systemAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_saveError != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.systemError.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  size: 16, color: colors.systemError),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _saveError!,
                                  style: TextStyle(
                                    color: colors.systemError,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _TestPrinterButton(
                    testing: _testing,
                    onPressed: _saving ? null : _testPrinter,
                  ),
                  Row(
                    children: [
                      // Lokal saqlangandan keyin yopish — «bekor qilish» emas:
                      // yozuv ro'yxatda bor, ekran uni ko'rsatishi uchun
                      // `true` qaytariladi.
                      _DialogButton.ghost(
                        label: _localOnlyWarning == null
                            ? S.current.strCancel
                            : 'Yopish',
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(
                                  context,
                                  _localOnlyWarning != null,
                                ),
                      ),
                      const SizedBox(width: 8),
                      // Yorliq o'zgarmaydi — ogohlantirishdan keyin ham aynan
                      // shu tugma qayta yuborishga urinadi.
                      _SavingButton(
                        saving: _saving,
                        label: isEdit ? S.current.strSave : S.current.strAdd,
                        onPressed: _saving ? null : _save,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Saqlangan yo'q — hozir formaga kiritilgan IP/port/ulanish turi bilan bitta
/// diagnostik chek yuboradi. Save tugmasidan mustaqil: kategoriya tanlovi
/// yoki boshqa Save-only qoidalar bu yerda talab qilinmaydi.
class _TestPrinterButton extends StatelessWidget {
  final bool testing;
  final VoidCallback? onPressed;

  const _TestPrinterButton({required this.testing, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = onPressed != null && !testing;
    return Material(
      color: colors.systemAccent.withOpacity(active ? 0.10 : 0.06),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: testing ? null : onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (testing)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.systemAccent,
                  ),
                )
              else
                Icon(Icons.print_outlined, size: 16, color: colors.systemAccent),
              const SizedBox(width: 8),
              Text(
                'Test Printer',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.systemAccent,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  const _DialogHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 16, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.buttonBrand.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: colors.buttonBrand, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colors.textDefault,
                    fontFamily: 'Inter',
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close_rounded,
                size: 20, color: colors.iconSecondary),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }
}

class _SavingButton extends StatelessWidget {
  final bool saving;
  final String label;
  final VoidCallback? onPressed;

  const _SavingButton({
    required this.saving,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: onPressed == null
          ? colors.buttonBrand.withOpacity(0.6)
          : colors.buttonBrand,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textOnBrand,
                    fontFamily: 'Inter',
                  ),
                ),
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final String? helper;
  final Widget child;
  const _LabeledField({required this.label, required this.child, this.helper});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textDefault,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 8),
        child,
        if (helper != null) ...[
          const SizedBox(height: 6),
          Text(
            helper!,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? formatters;

  const _TextField({
    required this.controller,
    this.hint,
    this.keyboard,
    this.validator,
    this.formatters,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      validator: validator,
      inputFormatters: formatters,
      // The printer dialog is a kiosk dialog — without this the field takes
      // focus and there is nothing to type with.
      onTap: () => FloatingKeyboard.openFor(
        context,
        controller,
        keyboardType: keyboard,
      ),
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: colors.textDefault,
        fontFamily: 'Inter',
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 14,
          color: colors.textSecondary.withOpacity(0.7),
          fontFamily: 'Inter',
        ),
        isDense: true,
        filled: true,
        fillColor: colors.bgSecondary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.buttonBrand, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.systemError),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.systemError, width: 1.5),
        ),
      ),
    );
  }
}

/// Shown in place of the ownership toggle when the printer being edited belongs
/// to a different terminal. That terminal's hardware — its USB cable, its
/// subnet — is not knowable from here, so the assignment is displayed rather
/// than offered; reassigning is done from the terminal that will own it.
class _ReadOnlyOwnerNotice extends StatelessWidget {
  final String label;

  const _ReadOnlyOwnerNotice({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.lan_rounded, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
                fontFamily: 'Inter',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceOption<T> {
  final T value;
  final String label;
  final IconData icon;
  final String helper;
  const _ChoiceOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.helper,
  });
}

class _SegmentedChoice<T> extends StatelessWidget {
  final T value;
  final List<_ChoiceOption<T>> options;
  final ValueChanged<T> onChanged;

  const _SegmentedChoice({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: options.map((o) {
        final selected = o.value == value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
                right: o == options.last ? 0 : 10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                color: selected
                    ? colors.buttonBrand.withOpacity(0.08)
                    : colors.bgSecondary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? colors.buttonBrand : colors.border,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onChanged(o.value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    child: Row(
                      children: [
                        Icon(
                          o.icon,
                          size: 18,
                          color: selected
                              ? colors.buttonBrand
                              : colors.iconSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                o.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? colors.buttonBrand
                                      : colors.textDefault,
                                  fontFamily: 'Inter',
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                o.helper,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.textSecondary,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: selected
                                ? colors.buttonBrand
                                : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? colors.buttonBrand
                                  : colors.border,
                              width: 1.5,
                            ),
                          ),
                          child: selected
                              ? const Icon(Icons.check_rounded,
                                  size: 11, color: Colors.white)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Ushbu kompyuterda o'rnatilgan Windows printerlari orasidan aniq birini
/// tanlash — eski "birinchi USB portlisini top" taxminidan farqli o'laroq,
/// bir nechta printer ulanganda ham noaniqlik qolmaydi.
class _UsbPrinterPicker extends StatelessWidget {
  final bool loading;
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final VoidCallback onRefresh;

  const _UsbPrinterPicker({
    required this.loading,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Saqlangan tanlov hozir ro'yxatda bo'lmasligi mumkin (printer vaqtincha
    // uzilgan) — dropdown yiqilib tushmasligi uchun uni ham ro'yxatga
    // qo'shamiz, alohida belgi bilan.
    final items = [...options];
    final missing = value != null && value!.isNotEmpty && !items.contains(value);
    if (missing) items.insert(0, value!);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: colors.bgSecondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: DropdownButtonHideUnderline(
              child: DropdownButtonFormField<String>(
                initialValue: items.contains(value) ? value : null,
                isExpanded: true,
                icon: Icon(Icons.expand_more_rounded, color: colors.textSecondary),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                  border: InputBorder.none,
                ),
                hint: Text(
                  loading ? 'Yuklanmoqda…' : 'Printer tanlang',
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textSecondary.withOpacity(0.7),
                    fontFamily: 'Inter',
                  ),
                ),
                items: items
                    .map(
                      (name) => DropdownMenuItem(
                        value: name,
                        child: Text(
                          missing && name == value ? '$name (mavjud emas)' : name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: missing && name == value
                                ? colors.systemError
                                : colors.textDefault,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: loading ? null : onChanged,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _GhostIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Ro\'yxatni yangilash',
          color: colors.buttonBrand,
          onTap: loading ? () {} : onRefresh,
        ),
      ],
    );
  }
}

class _CategoryMultiSelect extends StatelessWidget {
  final List<CategoryModel> categories;
  final Set<String> selected;
  final void Function(String id, bool selected) onChanged;

  const _CategoryMultiSelect({
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (categories.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.bgSecondary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: Text(
          'Kategoriyalar topilmadi',
          style: TextStyle(color: colors.textSecondary, fontFamily: 'Inter'),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: categories.map((c) {
            final isSelected = selected.contains(c.id);
            return _CategoryChip(
              label: c.name,
              selected: isSelected,
              onTap: () => onChanged(c.id, !isSelected),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? colors.buttonBrand : colors.bgDefault,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? colors.buttonBrand : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check_rounded,
                    size: 14, color: colors.textOnBrand),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? colors.textOnBrand : colors.textDefault,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
