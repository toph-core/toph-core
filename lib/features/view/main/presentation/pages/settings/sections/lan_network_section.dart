import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/core/services/lan_hub/leader_election_service.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_ports.dart';
import 'package:mary_ai_pos/core/services/lan_hub/local_ip_lookup.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/presentation/pages/settings/widgets/section_shell.dart';
import 'package:mary_ai_pos/generated/l10n.dart';

class LanNetworkSection extends StatefulWidget {
  const LanNetworkSection({super.key});

  @override
  State<LanNetworkSection> createState() => _LanNetworkSectionState();
}

class _LanNetworkSectionState extends State<LanNetworkSection> {
  late LanMode _mode;
  late String _serverIp;
  final _ipController = TextEditingController();
  Timer? _refreshTimer;
  bool _discovering = false;
  List<DiscoveredHub> _discovered = [];
  List<LocalAddress> _localAddresses = [];
  final _hubPortController = TextEditingController();
  final _discoveryPortController = TextEditingController();
  String? _portError;

  @override
  void initState() {
    super.initState();
    final lanHub = inject<LanHubService>();
    _mode = lanHub.mode;
    _serverIp = lanHub.serverIp;
    // Always shown as `ip:port` — the port is no longer a constant anyone can
    // assume, so hiding it would leave a follower unable to tell where it is
    // actually pointed.
    _ipController.text =
        _serverIp.isEmpty ? '' : '$_serverIp:${lanHub.serverPort}';
    _hubPortController.text = lanHub.preferredHubPort.toString();
    _discoveryPortController.text = lanHub.preferredDiscoveryPort.toString();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => setState(() {}),
    );
    _loadLocalAddresses();
  }

  /// Re-read on every mode change as well as at start: a terminal is often
  /// switched to Hub mode right after being moved onto the venue Wi-Fi, so the
  /// address list captured at screen-open time can already be stale.
  Future<void> _loadLocalAddresses() async {
    final addresses = await inject<LanHubService>().localAddresses();
    if (!mounted) return;
    setState(() => _localAddresses = addresses);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _ipController.dispose();
    _hubPortController.dispose();
    _discoveryPortController.dispose();
    super.dispose();
  }

  Future<void> _onModeChanged(LanMode mode) async {
    final lanHub = inject<LanHubService>();
    await lanHub.setMode(mode);
    await lanHub.restart();
    setState(() {
      _mode = mode;
      _discovered = [];
    });
    await _loadLocalAddresses();
  }

  Future<void> _onIpSaved() async {
    final lanHub = inject<LanHubService>();
    final parsed = parseHostPort(_ipController.text);
    if (parsed == null) {
      setState(() => _portError = "Manzil noto'g'ri. Namuna: 192.168.1.100:8765");
      return;
    }
    // An address typed without a port keeps whatever this terminal already had
    // rather than snapping back to the default — the saved value may have come
    // from a discovery announcement that knew better.
    final port = parsed.port ?? lanHub.serverPort;
    await lanHub.setServerIp(parsed.ip);
    await lanHub.setServerPort(port);
    await lanHub.restart();
    if (!mounted) return;
    setState(() {
      _serverIp = parsed.ip;
      _portError = null;
      _ipController.text = '${parsed.ip}:$port';
    });
  }

  Future<void> _onHubPortSaved() async {
    final value = int.tryParse(_hubPortController.text.trim());
    if (value == null || value < 1024 || value > 65535) {
      setState(() => _portError = "Port 1024 va 65535 orasida bo'lishi kerak");
      return;
    }
    final lanHub = inject<LanHubService>();
    await lanHub.setPreferredHubPort(value);
    await lanHub.restart();
    if (!mounted) return;
    setState(() {
      _portError = null;
      _hubPortController.text = lanHub.preferredHubPort.toString();
    });
  }

  Future<void> _onDiscoveryPortSaved() async {
    final value = int.tryParse(_discoveryPortController.text.trim());
    if (value == null || value < 1024 || value > 65535) {
      setState(() => _portError = "Port 1024 va 65535 orasida bo'lishi kerak");
      return;
    }
    final lanHub = inject<LanHubService>();
    await lanHub.setPreferredDiscoveryPort(value);
    // Election owns the discovery socket, so it has to be cycled for a new
    // preference to take effect — restarting only the hub would leave the
    // beacon on the old port.
    final election = inject<LeaderElectionService>();
    await election.stop();
    await lanHub.restart();
    await election.start();
    if (!mounted) return;
    setState(() {
      _portError = null;
      _discoveryPortController.text = lanHub.preferredDiscoveryPort.toString();
    });
  }

  Future<void> _onDiscoverTap() async {
    if (_discovering) return;
    setState(() {
      _discovering = true;
      _discovered = [];
    });
    final found = await inject<LanHubService>().discoverHubs();
    if (!mounted) return;
    setState(() {
      _discovering = false;
      _discovered = found;
    });
  }

  void _onDiscoveredPicked(DiscoveredHub hub) {
    _ipController.text = '${hub.ip}:${hub.port}';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lanHub = inject<LanHubService>();
    final colors = context.colors;

    return SectionShell(
      title: S.current.strNetworkLAN,
      subtitle: S.current.strDeviceSynchronization,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _SettingCard(
            icon: Icons.router_outlined,
            title: S.current.strMode,
            subtitle: S.current.strModeDescription,
            control: _SegmentedPicker<LanMode>(
              value: _mode,
              options: [
                _Option(
                  value: LanMode.disabled,
                  label: S.current.strDisabled,
                ),
                _Option(value: LanMode.server, label: S.current.strHub),
                _Option(value: LanMode.client, label: S.current.strClient),
              ],
              onChanged: _onModeChanged,
            ),
          ),
          if (_mode == LanMode.server) ...[
            const SizedBox(height: 14),
            _HubAddressCard(
              addresses: _localAddresses,
              port: lanHub.hubPort,
              isListening: lanHub.activeHubPort != null,
              bindError: lanHub.hubBindError,
              onRefresh: _loadLocalAddresses,
            ),
          ],
          if (_mode == LanMode.client) ...[
            const SizedBox(height: 14),
            _IpInputCard(
              controller: _ipController,
              onSave: _onIpSaved,
              discovering: _discovering,
              discovered: _discovered,
              onDiscover: _onDiscoverTap,
              onPickDiscovered: _onDiscoveredPicked,
            ),
          ],
          if (_mode != LanMode.disabled) ...[
            const SizedBox(height: 14),
            _PortSettingsCard(
              hubPortController: _hubPortController,
              discoveryPortController: _discoveryPortController,
              onHubPortSaved: _onHubPortSaved,
              onDiscoveryPortSaved: _onDiscoveryPortSaved,
              preferredHubPort: lanHub.preferredHubPort,
              activeHubPort: lanHub.activeHubPort,
              preferredDiscoveryPort: lanHub.preferredDiscoveryPort,
              activeDiscoveryPort: lanHub.activeDiscoveryPort,
              showHubPort: _mode == LanMode.server,
              error: _portError,
            ),
          ],
          const SizedBox(height: 14),
          _StatusCard(
            mode: _mode,
            bindError: _mode == LanMode.server ? lanHub.hubBindError : null,
            clientCount: _mode == LanMode.server ? lanHub.clientCount : null,
            isConnected:
                _mode == LanMode.client ? lanHub.isClientConnected : null,
            authFailReason: _mode == LanMode.client
                ? lanHub.lastAuthFailReason
                : null,
            colors: colors,
          ),
          if (_mode == LanMode.server && lanHub.conflictingHubIp != null) ...[
            const SizedBox(height: 14),
            _ConflictCard(conflictingIp: lanHub.conflictingHubIp!),
          ],
          const SizedBox(height: 14),
          _InfoCard(mode: _mode),
        ],
      ),
    );
  }
}

/// Hub-mode counterpart to [_IpInputCard]: instead of asking for an address,
/// it shows the ones this terminal already answers on, so a manager can read
/// one off and type it into a client by hand.
///
/// Exists because UDP auto-discovery reports the address a broadcast *left*
/// by, which on a machine with a docker bridge, a VPN tunnel or a second NIC
/// is often not the one any client can dial back. Ranking here is done by
/// interface name (see `listLocalIpv4Addresses`), which the hub knows and the
/// listening client never does.
class _HubAddressCard extends StatelessWidget {
  final List<LocalAddress> addresses;
  final int port;
  final bool isListening;
  final String? bindError;
  final Future<void> Function() onRefresh;

  const _HubAddressCard({
    required this.addresses,
    required this.port,
    required this.isListening,
    required this.bindError,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.buttonBrand.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.dns_outlined, color: c.buttonBrand, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bu qurilmaning IP manzillari',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textDefault,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isListening
                          ? 'Client qurilmalarga shu manzilni kiriting '
                              '(port: $port)'
                          : 'Hub hech qanday portni band qila olmadi',
                      style: TextStyle(
                        fontSize: 12,
                        color: isListening ? c.textSecondary : c.systemError,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Material(
                color: c.bgSecondary,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onRefresh,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, size: 16, color: c.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          'Yangilash',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: c.textSecondary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!isListening)
            Padding(
              padding: const EdgeInsets.only(left: 58),
              child: Text(
                'Quyidagi manzillar hozircha ishlamaydi — hub tinglamayapti. '
                "Portni o'zgartiring yoki portni band qilgan dasturni yoping."
                '${bindError == null ? '' : '\n($bindError)'}',
                style: TextStyle(
                  fontSize: 11,
                  color: c.systemError,
                  fontFamily: 'Inter',
                  height: 1.5,
                ),
              ),
            ),
          if (!isListening) const SizedBox(height: 10),
          if (addresses.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 58),
              child: Text(
                "Tarmoq manzili topilmadi — qurilma Wi-Fi yoki kabel orqali tarmoqqa ulanganini tekshiring.",
                style: TextStyle(
                  fontSize: 11,
                  color: c.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 58),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < addresses.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _AddressRow(
                      address: addresses[i],
                      port: port,
                      recommended: i == 0 && addresses[i].isPrivateLan,
                    ),
                  ],
                  if (addresses.any((a) => !a.isPrivateLan)) ...[
                    const SizedBox(height: 10),
                    Text(
                      "Bir nechta manzil bo'lsa, avval yuqoridagisini sinab ko'ring — "
                      "qolganlari virtual yoki tashqi tarmoq interfeyslari bo'lishi mumkin.",
                      style: TextStyle(
                        fontSize: 11,
                        color: c.textSecondary,
                        fontFamily: 'Inter',
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final LocalAddress address;
  final int port;
  final bool recommended;

  const _AddressRow({
    required this.address,
    required this.port,
    required this.recommended,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: recommended
              ? c.buttonBrand.withOpacity(0.12)
              : c.bgSecondary,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              final value = '${address.ip}:$port';
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$value nusxalandi'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 7,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${address.ip}:$port',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: recommended ? c.buttonBrand : c.textDefault,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.copy_rounded,
                    size: 14,
                    color: recommended ? c.buttonBrand : c.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          address.interface,
          style: TextStyle(
            fontSize: 11,
            color: c.textSecondary,
            fontFamily: 'Inter',
          ),
        ),
        if (recommended) ...[
          const SizedBox(width: 8),
          Text(
            '• tavsiya etiladi',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.systemSuccess,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ],
    );
  }
}

class _IpInputCard extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSave;
  final bool discovering;
  final List<DiscoveredHub> discovered;
  final VoidCallback onDiscover;
  final ValueChanged<DiscoveredHub> onPickDiscovered;

  const _IpInputCard({
    required this.controller,
    required this.onSave,
    required this.discovering,
    required this.discovered,
    required this.onDiscover,
    required this.onPickDiscovered,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.buttonBrand.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.lan_outlined,
                    color: colors.buttonBrand, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hub IP manzili',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textDefault,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Hub (server) qurilmaning manzili — ip yoki ip:port',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: controller,
                  // Not `.number`: the address now accepts an `ip:port` form,
                  // and a numeric keyboard offers no colon.
                  keyboardType: TextInputType.text,
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'Inter',
                    color: colors.textDefault,
                  ),
                  decoration: InputDecoration(
                    hintText: '192.168.1.100:8765',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: colors.bgSecondary,
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
                      borderSide:
                          BorderSide(color: colors.buttonBrand, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: colors.buttonBrand,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onSave,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Text(
                      'Saqlash',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textOnBrand,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const SizedBox(width: 58),
              Material(
                color: colors.bgSecondary,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: discovering ? null : onDiscover,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (discovering)
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.textSecondary,
                            ),
                          )
                        else
                          Icon(Icons.wifi_find_outlined,
                              size: 16, color: colors.textSecondary),
                        const SizedBox(width: 8),
                        Text(
                          discovering
                              ? 'Qidirilmoqda...'
                              : "Lokal tarmoqdan qidirish",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textSecondary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (discovered.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 58),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: discovered.map((hub) {
                  final label = '${hub.ip}:${hub.port}';
                  final selected = controller.text == label;
                  return Material(
                    color: selected
                        ? colors.buttonBrand.withOpacity(0.12)
                        : colors.bgSecondary,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onPickDiscovered(hub),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.dns_outlined,
                                size: 14,
                                color: selected
                                    ? colors.buttonBrand
                                    : colors.textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? colors.buttonBrand
                                    : colors.textDefault,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ] else if (!discovering) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 58),
              child: Text(
                "Hech qanday hub topilmadi. IP manzilni qo'lda kiriting yoki qayta qidiring.",
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lets an operator move either port off a collision, and shows what is
/// actually bound next to what was asked for.
///
/// Both ports auto-fall-back to the next free one (`candidatePorts`), so the
/// preference here is a starting point rather than a guarantee — which is why
/// "so'ralgan" and "faol" are shown as two numbers instead of one. A venue only
/// needs this field when something else holds the whole 10-port run.
class _PortSettingsCard extends StatelessWidget {
  final TextEditingController hubPortController;
  final TextEditingController discoveryPortController;
  final VoidCallback onHubPortSaved;
  final VoidCallback onDiscoveryPortSaved;
  final int preferredHubPort;
  final int? activeHubPort;
  final int preferredDiscoveryPort;
  final int? activeDiscoveryPort;
  final bool showHubPort;
  final String? error;

  const _PortSettingsCard({
    required this.hubPortController,
    required this.discoveryPortController,
    required this.onHubPortSaved,
    required this.onDiscoveryPortSaved,
    required this.preferredHubPort,
    required this.activeHubPort,
    required this.preferredDiscoveryPort,
    required this.activeDiscoveryPort,
    required this.showHubPort,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.buttonBrand.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    Icon(Icons.settings_ethernet, color: c.buttonBrand, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Portlar',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textDefault,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "Port band bo'lsa, keyingi bo'sh port avtomatik tanlanadi",
                      style: TextStyle(
                        fontSize: 12,
                        color: c.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (showHubPort) ...[
            _PortRow(
              label: 'Hub porti (WebSocket)',
              controller: hubPortController,
              preferred: preferredHubPort,
              active: activeHubPort,
              onSave: onHubPortSaved,
            ),
            const SizedBox(height: 12),
          ],
          _PortRow(
            label: 'Qidiruv porti (UDP)',
            controller: discoveryPortController,
            preferred: preferredDiscoveryPort,
            active: activeDiscoveryPort,
            onSave: onDiscoveryPortSaved,
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 58),
              child: Text(
                error!,
                style: TextStyle(
                  fontSize: 11,
                  color: c.systemError,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 58),
            child: Text(
              "Qidiruv porti barcha qurilmalarda bir xil bo'lishi kerak. "
              "Hub porti esa erkin — u qidiruv e'lonida uzatiladi.",
              style: TextStyle(
                fontSize: 11,
                color: c.textSecondary,
                fontFamily: 'Inter',
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int preferred;
  final int? active;
  final VoidCallback onSave;

  const _PortRow({
    required this.label,
    required this.controller,
    required this.preferred,
    required this.active,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fellBack = active != null && active != preferred;
    return Padding(
      padding: const EdgeInsets.only(left: 58),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textDefault,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  active == null
                      ? 'Faol emas'
                      : fellBack
                          ? "Faol: $active (so'ralgan $preferred band edi)"
                          : 'Faol: $active',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: fellBack ? FontWeight.w600 : FontWeight.w400,
                    color: active == null
                        ? c.systemError
                        : fellBack
                            ? c.buttonBrand
                            : c.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'Inter',
                color: c.textDefault,
              ),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: c.bgSecondary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: c.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: c.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: c.buttonBrand, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: c.bgSecondary,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onSave,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(
                  'Saqlash',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  final String conflictingIp;
  const _ConflictCard({required this.conflictingIp});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.systemError.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.warning_amber_rounded,
                color: c.systemError, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ikkita hub aniqlandi',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.systemError,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$conflictingIp manzilida boshqa bir qurilma ham Hub sifatida ishlayapti. '
                  "Faqat bitta qurilma Hub bo'lishi kerak — boshqasini Client yoki O'chirilgan rejimiga o'tkazing.",
                  style: TextStyle(
                    fontSize: 12,
                    color: c.textSecondary,
                    fontFamily: 'Inter',
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final LanMode mode;
  final String? bindError;
  final int? clientCount;
  final bool? isConnected;
  final String? authFailReason;
  final dynamic colors;

  const _StatusCard({
    required this.mode,
    this.bindError,
    required this.clientCount,
    required this.isConnected,
    this.authFailReason,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (mode) {
      case LanMode.server:
        final count = clientCount ?? 0;
        // A failed bind used to render identically to a healthy-but-empty hub,
        // which is the single most misleading state this screen could show —
        // the operator waits for terminals that can never arrive.
        if (bindError != null) {
          statusText = 'Hub ishga tushmadi — barcha portlar band';
          statusColor = c.systemError;
          statusIcon = Icons.error_outline;
          break;
        }
        statusText = count == 0
            ? 'Kutilmoqda — hech qanday qurilma ulanmagan'
            : '$count ta qurilma ulangan';
        statusColor = count > 0 ? c.systemSuccess : c.textSecondary;
        statusIcon = count > 0
            ? Icons.check_circle_outline
            : Icons.radio_button_unchecked;
        break;
      case LanMode.client:
        final connected = isConnected ?? false;
        final reason = authFailReason;
        statusText = connected
            ? 'Hub ga ulangan'
            : (reason != null
                ? 'Hub rad etdi ($reason) — qayta urinmoqda...'
                : 'Ulanmadi — qayta urinmoqda...');
        statusColor = connected ? c.systemSuccess : c.systemError;
        statusIcon = connected
            ? Icons.check_circle_outline
            : Icons.error_outline;
        break;
      case LanMode.disabled:
        statusText = 'LAN sinxronizatsiya o\'chirilgan';
        statusColor = c.textSecondary;
        statusIcon = Icons.radio_button_unchecked;
        break;
    }

    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(statusIcon, color: statusColor, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ulanish holati',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textDefault,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 3),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 12,
                  color: statusColor,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final LanMode mode;
  const _InfoCard({required this.mode});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = switch (mode) {
      LanMode.server =>
        'Bu qurilma Hub sifatida ishlaydi. Boshqa POS qurilmalari uning IP manziliga ulanadi. '
            "Yuqoridagi ro'yxatdan manzilni olib, client qurilmalarga kiriting.",
      LanMode.client =>
        'Bu qurilma Client sifatida ishlaydi. Hub (server) qurilmaning IP manzilini kiriting va "Saqlash" ni bosing.',
      LanMode.disabled =>
        'LAN sinxronizatsiya o\'chirilgan. Internet bo\'lganda faqat bulut orqali sinxronlashadi.',
    };

    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.buttonBrand.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.info_outline, color: c.buttonBrand, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: c.textSecondary,
                fontFamily: 'Inter',
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Option<T> {
  final T value;
  final String label;
  final String? flag;
  const _Option({required this.value, required this.label, this.flag});
}

class _SegmentedPicker<T> extends StatelessWidget {
  final T value;
  final List<_Option<T>> options;
  final ValueChanged<T> onChanged;

  const _SegmentedPicker({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((o) {
          final selected = o.value == value;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: selected ? colors.bgDefault : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => onChanged(o.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (o.flag != null) ...[
                        Text(o.flag!, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        o.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? colors.buttonBrand
                              : colors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget control;

  const _SettingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.buttonBrand.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: colors.buttonBrand, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textDefault,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 3),
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
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }
}
