import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app_controller.dart';
import '../../model/models.dart';

/// Binds scene dialogs to the shared controller and the app lifecycle.
class SceneTransport extends ChangeNotifier with WidgetsBindingObserver {
  SceneTransport(this.controller) {
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(notifyListeners);
  }

  final AppController controller;
  bool get ready => controller.canSend;
  bool get previewing => controller.previewing;
  bool get failed => controller.message == 'commandFailed';
  int get sensitivity => controller.sensitivity;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) controller.setForeground(true);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      controller.setForeground(false);
    }
  }

  void useShared(Fields shortcut) => unawaited(controller.applyShortcut(shortcut));
  Future<void> playVoice(int mode) => controller.setVoiceMode(mode);
  void changeSensitivity(int value) => controller.setMicSensitivity(value);
  Future<void> playEffect(int id, {bool preview = false}) =>
      controller.setEffect(id, preview: preview);
  Future<void> playColors(List<List<int>> colors, int interval, int intensity,
      {bool preview = true,
      ({List<List<int>> colors, int interval, int intensity}) Function()? draft}) =>
      controller.playDraft(colors, interval, intensity, preview: preview, draft: draft);
  void stopPreview({bool restore = true}) => controller.stopDraftPreview(restore: restore);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(notifyListeners);
    controller.stopDraftPreview(restore: false);
    super.dispose();
  }
}
