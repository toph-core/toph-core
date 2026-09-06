import 'dart:convert';

/// `GET /api/v1/settings/printer-settings` — `data[]` elementi.
class PrinterSettingEntry {
  const PrinterSettingEntry({
    required this.id,
    required this.ip,
    required this.port,
    required this.type,
    required this.connectedEntityIds,
    this.name = '',
    this.connectionType = 'cable',
    this.branchId = '',
    this.ownerCashRegisterId = '',
  });

  final String id;
  final String ip;
  final int port;

  /// Operator ko'radigan nom («Oshxona», «Bar»). Backendda `name` ustuni —
  /// bitta terminalda bir nechta USB printer bo'lishi mumkin, ular faqat shu
  /// nom bilan farqlanadi (`uq_printer_settings_identity_active`).
  final String name;

  /// `category` yoki `close_check`
  final String type;
  final List<String> connectedEntityIds;

  /// API: **`cable`** (LAN), **`wlan`** (Wi‑Fi), **`usb`** (egasining Windows
  /// spooler'i orqali). `usb` uchun `ip`/`port` bo'sh.
  final String connectionType;

  /// Bu printer qaysi filialga tegishli — bo'sh bo'lsa, eski (filialsiz)
  /// yozuv, hamma filialda ko'rinadi.
  final String branchId;

  /// **Bu printerga jismonan yeta oladigan yagona POS nusxasi** —
  /// `cash_register_id`. Bo'sh bo'lsa egasiz: har qanday terminal to'g'ridan-
  /// to'g'ri chop etadi (75_printer_settings_owner dan oldingi xulq).
  ///
  /// Terminal-lokal `print_terminal_id` emas, aynan kassa identifikatori
  /// ishlatiladi: u har bir POS tokenida `cash_register_id` da'vosi sifatida
  /// keladi, shuning uchun backend ham, qo'shni terminal ham uni nomlay
  /// oladi.
  final String ownerCashRegisterId;

  bool get isCloseCheck => type == 'close_check';
  bool get isCategory => type == 'category';

  /// Egasi yo'q — har qanday terminal to'g'ridan-to'g'ri ulanadi.
  bool get isUnowned => ownerCashRegisterId.trim().isEmpty;

  /// `usb` — manzilsiz: egasining mashinasidagi spooler orqali chop etiladi,
  /// `ip`/`port` ma'noga ega emas.
  bool get isAddressless => connectionType.toLowerCase() == 'usb';

  /// `cable` / `wlan` — tarmoq TCP; `wifi` / `lan` / `ethernet` sinonim.
  bool get isNetworkTcp {
    switch (connectionType.toLowerCase()) {
      case 'cable':
      case 'wlan':
      case 'wifi':
      case 'lan':
      case 'ethernet':
        return true;
      default:
        return false;
    }
  }

  /// [cashRegisterId] shu yozuvning egasimi. Egasiz yozuv uchun `false` —
  /// «egasiz» «meniki» degani emas, «hech kimniki, hamma yeta oladi» degani.
  bool isOwnedBy(String cashRegisterId) {
    final owner = ownerCashRegisterId.trim();
    if (owner.isEmpty) return false;
    return owner.toLowerCase() == cashRegisterId.trim().toLowerCase();
  }

  PrinterSettingEntry copyWith({
    String? id,
    String? ip,
    int? port,
    String? name,
    String? type,
    List<String>? connectedEntityIds,
    String? connectionType,
    String? branchId,
    String? ownerCashRegisterId,
  }) {
    return PrinterSettingEntry(
      id: id ?? this.id,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      name: name ?? this.name,
      type: type ?? this.type,
      connectedEntityIds: connectedEntityIds ?? this.connectedEntityIds,
      connectionType: connectionType ?? this.connectionType,
      branchId: branchId ?? this.branchId,
      ownerCashRegisterId: ownerCashRegisterId ?? this.ownerCashRegisterId,
    );
  }

  factory PrinterSettingEntry.fromJson(Map<String, dynamic> json) {
    final rawIds = json['connected_entity_ids'] ?? json['connectedEntityIds'];
    final ids = <String>[];
    if (rawIds is List) {
      for (final e in rawIds) {
        final s = e.toString().trim();
        if (s.isNotEmpty) ids.add(s);
      }
    }

    var connectionType =
        (json['connection_type'] ?? json['connectionType'] ?? 'cable')
            .toString()
            .trim();
    if (connectionType.isEmpty) connectionType = 'cable';

    // `usb` uchun port normalizatsiyasi qilinmaydi: backend 0 saqlaydi va
    // 9100 ga «tuzatish» manzilsiz printerga soxta manzil qaytarib beradi —
    // aynan shu narsa ilgari hamma USB printerni bitta kalitga yopishtirgan.
    final isAddressless = connectionType.toLowerCase() == 'usb';
    var port = isAddressless ? 0 : 9100;
    final p = json['port'];
    if (p is int) {
      port = p;
    } else if (p != null) {
      port = int.tryParse(p.toString()) ?? port;
    }
    if (!isAddressless && (port <= 0 || port > 65535)) port = 9100;

    return PrinterSettingEntry(
      id: json['id']?.toString() ?? '',
      ip: json['ip']?.toString().trim() ?? '',
      port: port,
      name: json['name']?.toString().trim() ?? '',
      type: (json['type']?.toString() ?? '').trim(),
      connectedEntityIds: ids,
      connectionType: connectionType,
      branchId: (json['branch_id'] ?? json['branchId'])?.toString().trim() ?? '',
      ownerCashRegisterId:
          (json['owner_cash_register_id'] ?? json['ownerCashRegisterId'])
                  ?.toString()
                  .trim() ??
              '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ip': ip,
        'port': port,
        'name': name,
        'type': type,
        'connection_type': connectionType,
        'branch_id': branchId,
        'owner_cash_register_id': ownerCashRegisterId,
        'connected_entity_ids': connectedEntityIds,
      };

  static List<PrinterSettingEntry> listFromJsonList(List<dynamic> raw) => raw
      .map(
        (e) => PrinterSettingEntry.fromJson(
          Map<String, dynamic>.from(e as Map),
        ),
      )
      .toList();

  static String encodeList(List<PrinterSettingEntry> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());
}
