import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Низкоуровневый слой хранения данных приложения.
/// Все ключи централизованы здесь — не разбросаны по экранам.
class AppStorage {
  static const _keyRoomsScanned = 'rooms_scanned';
  static const _keyItemsRecognized = 'items_recognized';
  static const _keyRecognitionSessions = 'recognition_sessions';
  static const _keyScanSessions = 'scan_sessions';

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

  // ── История AR-сканирований ───────────────────────────────────────────────

  List<ScanSession> get scanSessions {
    final raw = _prefs.getStringList(_keyScanSessions) ?? [];
    return raw
        .map((s) => ScanSession.fromJson(jsonDecode(s)))
        .toList()
        .reversed
        .toList();
  }

  Future<void> saveScanSession(ScanSession session) async {
    final raw = _prefs.getStringList(_keyScanSessions) ?? [];
    raw.add(jsonEncode(session.toJson()));
    await _prefs.setStringList(_keyScanSessions, raw);
  }

  Future<void> clearAll() async {
    await _prefs.remove(_keyRoomsScanned);
    await _prefs.remove(_keyItemsRecognized);
    await _prefs.remove(_keyRecognitionSessions);
    await _prefs.remove(_keyScanSessions);
  }
}

/// Одна сессия AR-сканирования планировки.
class ScanSession {
  final DateTime timestamp;
  final int planesDetected;
  final double totalFloorArea;

  ScanSession({
    required this.timestamp,
    required this.planesDetected,
    required this.totalFloorArea,
  });

  factory ScanSession.fromJson(Map<String, dynamic> json) => ScanSession(
        timestamp: DateTime.parse(json['timestamp'] as String),
        planesDetected: json['planes_detected'] as int,
        totalFloorArea: (json['total_floor_area'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'planes_detected': planesDetected,
        'total_floor_area': totalFloorArea,
      };
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
