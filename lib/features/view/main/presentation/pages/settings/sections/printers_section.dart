import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mary_ai_pos/core/components/flush_bars.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/service/printer/printer_config_storage.dart';
import 'package:mary_ai_pos/core/service/printer/printer_service.dart';
import 'package:mary_ai_pos/core/service/printer/printer_setting_entry.dart';
import 'package:mary_ai_pos/core/services/cache/cache_service.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/data/models/category/category_model.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/main_repository.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/settings/widgets/section_shell.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class PrintersSection extends StatefulWidget {
  const PrintersSection({super.key});

  @override
  State<PrintersSection> createState() => _PrintersSectionState();
}

class _PrintersSectionState extends State<PrintersSection> {
  final MainRepository _repository = inject<MainRepository>();
  final PrinterConfigStorage _storage = inject<PrinterConfigStorage>();

  bool _loading = true;
  List<PrinterSettingEntry> _items = const [];
  List<CategoryModel> _categories = const [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  /// Printer ro'yxati — **shu qurilmadagi** lokal saqlashdan, hech qanday
  /// tarmoq so'rovisiz (hech qachon xato bermaydi). Kategoriya nomlari esa
  /// faqat ko'rsatish uchun — avval keshdan, so'ng eng yaxshi urinish sifatida
  /// backenddan yangilanadi; muvaffaqiyatsiz bo'lsa jim qoladi.
  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _items = _storage.listEntries();
    });
    final cachedCats = inject<CacheService>().getCategories();
    if (cachedCats.isNotEmpty && mounted) {
      setState(() {
        _categories =
            cachedCats.map((e) => CategoryModel.fromJson(e)).toList();
      });
    }
    setState(() => _loading = false);
    final result = await _repository.getCategories();
    final categories = result.fold((_) => null, (r) => r);
    if (categories == null) {
      // Kategoriya nomlarini yangilab bo'lmadi — jim o'tamiz, printer
      // ro'yxati baribir lokal holatdan to'liq ko'rsatiladi.
      debugPrint('[PrintersSection] Kategoriyalarni yuklab bo\'lmadi');
      return;
    }
    if (!mounted) return;
    setState(() => _categories = categories);
  }

  Future<void> _openEditor({PrinterSettingEntry? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PrinterEditDialog(
        existing: existing,
        categories: _categories,
        repository: _repository,
        storage: _storage,
      ),
    );
    if (saved == true && mounted) {
      _loadAll();
    }
  }

  Future<void> _confirmDelete(PrinterSettingEntry item) async {
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
    unawaited(
      _repository.deletePrinterSetting(item.id).then((result) {
        result.fold(
          (f) => debugPrint('[PrintersSection] Backend delete xatosi (e\'tiborsiz): $f'),
          (_) {},
        );
      }),
    );
    if (!mounted) return;
    inject<CacheService>().removeUsbPrinterName(item.id);
    _loadAll();
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
    final isUsb = entry.connectionType == 'usb';
    String? windowsPrinterName;
    if (isUsb) {
      windowsPrinterName = inject<CacheService>().getUsbPrinterName(entry.id);
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
                      Text(
                        '${entry.ip}:${entry.port}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.textDefault,
                          fontFamily: 'Inter',
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _Badge(
                        color: typeColor,
                        label: isCloseCheck ? S.current.strCheckPrinter : S.current.strCategory,
                      ),
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
  final MainRepository repository;
  final PrinterConfigStorage storage;

  const _PrinterEditDialog({
    required this.existing,
    required this.categories,
    required this.repository,
    required this.storage,
  });

  @override
  State<_PrinterEditDialog> createState() => _PrinterEditDialogState();
}

class _PrinterEditDialogState extends State<_PrinterEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ipCtrl;
  late final TextEditingController _portCtrl;
  String _type = 'category';
  String _connection = 'cable';
  final Set<String> _selectedCategoryIds = {};
  bool _saving = false;
  String? _saveError;
  bool _testing = false;
  bool? _testOk; // null = no test run yet
  String? _testMessage;

  // USB (Windows spooler) — bu qurilmada o'rnatilgan printerlar ro'yxati va
  // tanlangan nom. Backend bilan sinxronlanmaydi (CacheService, faqat lokal).
  String? _windowsPrinterName;
  List<String> _localPrinters = const [];
  bool _loadingLocalPrinters = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _ipCtrl = TextEditingController(text: e?.ip ?? '');
    _portCtrl = TextEditingController(text: (e?.port ?? 9100).toString());
    if (e != null) {
      _type = e.type.isNotEmpty ? e.type : 'category';
      _connection = e.connectionType.isNotEmpty ? e.connectionType : 'cable';
      _selectedCategoryIds.addAll(e.connectedEntityIds);
      if (_connection == 'usb') {
        _windowsPrinterName = inject<CacheService>().getUsbPrinterName(e.id);
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
    super.dispose();
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

  /// Lokal saqlash — har doim ishlaydi, birlamchi manba. Backendga yuborish
  /// alohida, eng yaxshi urinish sifatida ([_pushToBackendBestEffort]): u
  /// muvaffaqiyatsiz bo'lsa ham (masalan tarmoq yo'q) Save baribir
  /// muvaffaqiyatli yakunlanadi — hozircha shu tarzda sinovdan o'tkazilmoqda.
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
    });

    // USB — IP/port backend sxemasi uchun placeholder, chop etishda
    // ishlatilmaydi (haqiqiy nishon — [_windowsPrinterName] — faqat shu
    // qurilmada lokal saqlanadi, pastda).
    final ip = _connection == 'usb' ? '127.0.0.1' : _ipCtrl.text.trim();
    final port = _connection == 'usb' ? 9100 : int.parse(_portCtrl.text.trim());
    final entryId = widget.existing?.id ?? widget.storage.generateLocalId();
    final entry = PrinterSettingEntry(
      id: entryId,
      ip: ip,
      port: port,
      type: _type,
      connectedEntityIds:
          _type == 'category' ? _selectedCategoryIds.toList() : <String>[],
      connectionType: _connection,
    );

    await widget.storage.upsertEntry(entry);

    final cache = inject<CacheService>();
    if (_connection == 'usb' && _windowsPrinterName != null) {
      await cache.saveUsbPrinterName(entryId, _windowsPrinterName!);
    } else {
      // Turi 'usb'dan boshqasiga o'zgargan bo'lishi mumkin — eski lokal
      // tanlovni qoldirmaymiz.
      await cache.removeUsbPrinterName(entryId);
    }

    unawaited(_pushToBackendBestEffort(entry));

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  /// Backendga yozishga urinadi — muvaffaqiyat/muvaffaqiyatsizligi Save
  /// natijasiga ta'sir qilmaydi, faqat log qoldiradi. Yangi yozuv uchun
  /// backend berishi mumkin bo'lgan boshqa id'ga qasddan almashtirilmaydi —
  /// lokal [entryId] shu qurilmada USB tanlovi va print-time qidiruvi uchun
  /// yagona manba bo'lib qoladi.
  Future<void> _pushToBackendBestEffort(PrinterSettingEntry entry) async {
    final body = {
      'ip': entry.ip,
      'port': entry.port,
      'type': entry.type,
      'connection_type': entry.connectionType,
      'connected_entity_ids': entry.connectedEntityIds,
    };
    final result = await widget.repository.pushPrinterSetting(
      body,
      existingId: widget.existing?.id,
    );
    result.fold(
      (f) => debugPrint(
        '[PrinterEditDialog] Backend yozish xatosi (e\'tiborsiz, '
        'lokal saqlandi): $f',
      ),
      (_) => debugPrint('[PrinterEditDialog] Backendga yozildi: ${entry.id}'),
    );
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
              onClose: () => Navigator.pop(context, false),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                      _DialogButton.ghost(
                        label: S.current.strCancel,
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context, false),
                      ),
                      const SizedBox(width: 8),
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
