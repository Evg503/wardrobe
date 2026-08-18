import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Низкоуровневый слой хранения данных приложения.
/// Все ключи централизованы здесь — не разбросаны по экранам.
class AppStorage {
  static const _keyRoomsScanned = 'rooms_scanned';
  static const _keyItemsRecognized = 'items_recognized';
  static const _keyRecognitionSessions = 'recognition_sessions';

  final SharedPreferences _prefs;

  AppStorage._(this._prefs);

  static Future<AppStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return AppStorage._(prefs);
  }

  // ── Счётчики ──────────────────────────────────────────────────────────────

  int get roomsScanned => _prefs.getInt(_keyRoomsScanned) ?? 0;
  int get itemsRecognized => _prefs.getInt(_keyItemsRecognized) ?? 0;

  Future<void> incrementRoomsScanned() async {
    await _prefs.setInt(_keyRoomsScanned, roomsScanned + 1);
  }

  Future<void> addItemsRecognized(int count) async {
    await _prefs.setInt(_keyItemsRecognized, itemsRecognized + count);
  }

  // ── История сессий распознавания ──────────────────────────────────────────

  List<RecognitionSession> get recognitionSessions {
    final raw = _prefs.getStringList(_keyRecognitionSessions) ?? [];
    return raw
        .map((s) => RecognitionSession.fromJson(jsonDecode(s)))
        .toList()
        .reversed
        .toList(); // новые сверху
  }

  Future<void> saveRecognitionSession(RecognitionSession session) async {
    final raw = _prefs.getStringList(_keyRecognitionSessions) ?? [];
    raw.add(jsonEncode(session.toJson()));
    await _prefs.setStringList(_keyRecognitionSessions, raw);
  }

  Future<void> clearAll() async {
    await _prefs.remove(_keyRoomsScanned);
    await _prefs.remove(_keyItemsRecognized);
    await _prefs.remove(_keyRecognitionSessions);
  }
}

// ── Модели ────────────────────────────────────────────────────────────────────

/// Одна сессия распознавания объектов.
class RecognitionSession {
  final DateTime timestamp;
  final List<RecognizedItem> items;

  RecognitionSession({
    required this.timestamp,
    required this.items,
  });

  int get itemCount => items.length;

  factory RecognitionSession.fromJson(Map<String, dynamic> json) {
    return RecognitionSession(
      timestamp: DateTime.parse(json['timestamp'] as String),
      items: (json['items'] as List)
          .map((i) => RecognizedItem.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
      };
}

/// Один распознанный предмет внутри сессии.
class RecognizedItem {
  final String label;
  final String category;
  final double confidence;

  RecognizedItem({
    required this.label,
    required this.category,
    required this.confidence,
  });

  factory RecognizedItem.fromJson(Map<String, dynamic> json) {
    return RecognizedItem(
      label: json['label'] as String,
      category: json['category'] as String,
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'category': category,
        'confidence': confidence,
      };
}
