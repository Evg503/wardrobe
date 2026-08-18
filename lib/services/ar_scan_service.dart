import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

/// Обнаруженная плоскость (пол, стена, потолок).
class DetectedPlane {
  final String id;
  final PlaneType type;
  /// Центр плоскости в мировых координатах (метры).
  final Vector3 center;
  /// Размер ограничивающего прямоугольника (ширина × высота, метры).
  final Vector2 extent;

  DetectedPlane({
    required this.id,
    required this.type,
    required this.center,
    required this.extent,
  });

  double get area => extent.x * extent.y;
}

enum PlaneType { horizontal, vertical }

/// Результат завершённого AR-сканирования.
class ScanResult {
  final List<DetectedPlane> planes;
  final DateTime timestamp;

  ScanResult({required this.planes, required this.timestamp});

  /// Суммарная площадь горизонтальных плоскостей (пол) в м².
  double get totalFloorArea => planes
      .where((p) => p.type == PlaneType.horizontal)
      .fold(0.0, (sum, p) => sum + p.area);

  int get roomCount => planes.where((p) => p.type == PlaneType.horizontal).length;
}

/// Сервис AR-сканирования.
///
/// На iOS использует ARKit (через arkit_plugin) для детектирования плоскостей.
/// На Android возвращает заглушку — полноценный ARCore требует отдельного
/// нативного плагина, который будет добавлен в следующей итерации.
class ArScanService extends ChangeNotifier {
  final List<DetectedPlane> _planes = [];
  bool _isScanning = false;
  String? _errorMessage;

  List<DetectedPlane> get planes => List.unmodifiable(_planes);
  bool get isScanning => _isScanning;
  String? get errorMessage => _errorMessage;
  bool get isSupported => Platform.isIOS; // ARCore support — next iteration

  void startScan() {
    _planes.clear();
    _isScanning = true;
    _errorMessage = null;
    notifyListeners();
  }

  void stopScan() {
    _isScanning = false;
    notifyListeners();
  }

  /// Вызывается из ARKitSceneView при обнаружении/обновлении плоскости.
  void updatePlane(DetectedPlane plane) {
    final idx = _planes.indexWhere((p) => p.id == plane.id);
    if (idx >= 0) {
      _planes[idx] = plane;
    } else {
      _planes.add(plane);
    }
    notifyListeners();
  }

  void removePlane(String id) {
    _planes.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  ScanResult buildResult() {
    return ScanResult(
      planes: List.from(_planes),
      timestamp: DateTime.now(),
    );
  }

  void reset() {
    _planes.clear();
    _isScanning = false;
    _errorMessage = null;
    notifyListeners();
  }

  void setError(String message) {
    _errorMessage = message;
    _isScanning = false;
    notifyListeners();
  }
}
