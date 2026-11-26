import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app_controller.dart';
import '../../model/models.dart';
import '../../protocol.dart' as wire;

/// Binds scene dialogs to the shared controller and the app lifecycle.
class SceneTransport extends ChangeNotifier with WidgetsBindingObserver {
  SceneTransport(this.controller) {
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_controllerChanged);
  }

  final AppController controller;
  bool get ready => controller.canSend;
  bool get previewing => controller.previewing;
  bool get failed => controller.message == 'commandFailed';
  int get sensitivity => controller.sensitivity;
  String? _selectedCard;
  bool isSelected(String card) => _selectedCard == card;
  VoidCallback? _observeStart;

  void _controllerChanged() {
    _observeStart?.call();
    notifyListeners();
  }

  // Voice and shortcut starts return no result. Listen for a fresh successful
  // playback frame during the start, not a preparation or sensitivity write.
  Future<void> _start(String card, String command, String field, Object value,
      Future<void> Function() play) async {
    final previousValues = controller.lastValues;
    void observe() {
      final values = controller.lastValues;
      if (!identical(values, previousValues) && controller.lastCommand == command &&
          values[field] == value) {
        _selectedCard = card;
        _observeStart = null;
      }
    }

    _observeStart = observe;
    try {
      await play();
    } finally {
      if (identical(_observeStart, observe)) _observeStart = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) controller.setForeground(true);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      controller.setForeground(false);
    }
  }

  void playShortcut(String card, Fields shortcut, Fields firstStep) {
    final effect = firstStep['effect'];
    unawaited(effect == null
        ? _start(card, 'color', 'hex', rgbHex(firstStep['rgb'] as List<int>),
            () => controller.applyShortcut(shortcut))
        : _start(card, 'effectNamed', 'id', effect, () => controller.applyShortcut(shortcut)));
  }

  Future<void> playVoice(int mode) =>
      _start('scene-voice-$mode', 'musicMode', 'id', mode, () => controller.setVoiceMode(mode));
  void changeSensitivity(int value) => controller.setMicSensitivity(value);
  Future<void> playEffect(int id, {bool preview = false}) async {
    if (preview) {
      await controller.setEffect(id, preview: true);
    } else {
      await _start('included-effect-$id', id == wire.autoEffect ? 'autoCycle' : 'effectNamed',
        'id', id, () async { await controller.setEffect(id); });
    }
  }
  Future<void> playColors(List<List<int>> colors, int interval, int intensity,
      {bool preview = true,
      ({List<List<int>> colors, int interval, int intensity}) Function()? draft}) =>
      controller.playDraft(colors, interval, intensity, preview: preview, draft: draft);
  void stopPreview({bool restore = true}) => controller.stopDraftPreview(restore: restore);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _observeStart = null;
    controller.removeListener(_controllerChanged);
    controller.stopDraftPreview(restore: false);
    super.dispose();
  }
}
