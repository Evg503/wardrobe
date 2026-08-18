import 'package:flutter/material.dart';
import 'app_storage.dart';
import 'object_detection_service.dart';

/// Глобальное состояние приложения.
/// Держит счётчики и историю, пишет в AppStorage при изменениях.
/// Передаётся вниз по дереву виджетов через InheritedWidget (AppStateScope).
class AppState extends ChangeNotifier {
  final AppStorage _storage;

  AppState._(this._storage);

  static Future<AppState> create() async {
    final storage = await AppStorage.create();
    return AppState._(storage);
  }

  // ── Геттеры ───────────────────────────────────────────────────────────────

  int get roomsScanned => _storage.roomsScanned;
  int get itemsRecognized => _storage.itemsRecognized;
  List<RecognitionSession> get recognitionSessions =>
      _storage.recognitionSessions;

  // ── Действия ──────────────────────────────────────────────────────────────

  /// Вызывается когда завершено сканирование планировки.
  Future<void> onRoomScanned() async {
    await _storage.incrementRoomsScanned();
    notifyListeners();
  }

  /// Вызывается когда завершена сессия распознавания объектов.
  Future<void> onRecognitionFinished(List<DetectedObject> detected) async {
    if (detected.isEmpty) return;

    final items = detected
        .map((d) => RecognizedItem(
              label: d.label,
              category: d.category,
              confidence: d.confidence,
            ))
        .toList();

    final session = RecognitionSession(
      timestamp: DateTime.now(),
      items: items,
    );

    await _storage.saveRecognitionSession(session);
    await _storage.addItemsRecognized(items.length);
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _storage.clearAll();
    notifyListeners();
  }
}

// ── InheritedWidget ───────────────────────────────────────────────────────────

/// Провайдер AppState для дерева виджетов.
/// Используй AppStateScope.of(context) для доступа к состоянию.
class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    super.key,
    required AppState state,
    required Widget child,
  }) : super(notifier: state, child: child);

  static AppState of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope not found in widget tree');
    return scope!.notifier!;
  }
}
