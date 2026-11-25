import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import 'notice.dart';

class BluetoothCard extends StatelessWidget {
  const BluetoothCard({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Material(
      color: Notice.warningSurface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Notice.warningColor)),
      child: Padding(padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          Notice(c.text('bluetoothOffBody'), kind: NoticeKind.warning, live: true,
            heading: c.text('bluetoothOffTitle'), icon: Icons.bluetooth_disabled, prominent: true),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xff7e22ce), foregroundColor: Colors.white),
            onPressed: c.requestingBluetooth ? null : c.requestEnableBluetooth,
            child: Text(c.text('bluetoothTurnOn'), textAlign: TextAlign.center)),
          if (c.message == 'bluetoothEnableFailed')
            Notice(c.text('bluetoothEnableFailed'), kind: NoticeKind.error, live: true),
        ]),
      ),
    );
  }
}
