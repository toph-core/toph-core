import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/services/lan_hub/lan_hub_service.dart';
import 'package:mary_ai_pos/di.dart';

/// Analogue of `OfflineBanner` for LAN `client` mode (Phase 4 sole-uplink):
/// shows a strip when this terminal depends on a leader for cloud sync but
/// currently can't reach it. Deliberately distinct from `OfflineBanner` — a
/// follower can have perfectly good internet of its own and still be "solo"
/// here, since `client` mode routes all outbox sync through the leader, not
/// directly (see offline-first-architecture-plan.md §11 Phase 4).
///
/// Reads `mode` inside the `StreamBuilder`'s callback rather than gating on
/// it separately — `mode` itself has no stream, but every mode change in
/// this app goes through `LanHubService.restart()`, which always calls
/// `disconnect()` first, and that always fires `onClientConnectionChanged`.
/// Piggybacking the mode check on that same rebuild trigger means this
/// banner doesn't need a polling timer of its own to notice a mode change.
class LanSoloBanner extends StatelessWidget {
  const LanSoloBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final lanHub = inject<LanHubService>();
    return StreamBuilder<bool>(
      initialData: lanHub.isClientConnected,
      stream: lanHub.onClientConnectionChanged,
      builder: (context, snapshot) {
        final solo = lanHub.mode == LanMode.client && !(snapshot.data ?? false);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: solo ? 32 : 0,
          color: const Color(0xFFEF6C00),
          child: solo
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lan_outlined, size: 15, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      "Hub bilan aloqa yo'q — mahalliy rejimda ishlayapsiz",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }
}
