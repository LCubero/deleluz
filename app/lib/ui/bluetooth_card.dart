import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import 'glow_glass.dart';

class BluetoothCard extends StatelessWidget {
  const BluetoothCard({super.key, required this.controller});

  final AppController controller;
  static const _warn = Color(0xfffbbf24);
  static const _surface = Color(0xff251e2c);

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final style = Theme.of(context).textTheme;
    return Material(
      color: _surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: _warn)),
      child: Padding(padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          Row(spacing: 10, children: [
            DecoratedBox(decoration: BoxDecoration(color: const Color(0xff0a0918),
              borderRadius: BorderRadius.circular(14)),
              child: const SizedBox.square(dimension: 44, child: Icon(Icons.bluetooth_disabled, color: _warn))),
            Expanded(child: Semantics(liveRegion: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.text('bluetoothOffTitle'), style: style.titleMedium?.copyWith(color: _warn)),
                Text(c.text('bluetoothOffBody'), style: style.bodyMedium?.copyWith(color: glowMuted)),
              ]))),
          ]),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xff7e22ce), foregroundColor: Colors.white),
            onPressed: c.requestingBluetooth ? null : c.requestEnableBluetooth,
            child: Text(c.text('bluetoothTurnOn'), textAlign: TextAlign.center)),
          if (c.message == 'bluetoothEnableFailed')
            Semantics(liveRegion: true, child: Text(c.text('bluetoothEnableFailed'))),
        ]),
      ),
    );
  }
}
