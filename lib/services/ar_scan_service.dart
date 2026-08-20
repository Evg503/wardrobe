import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  int get roomCount =>
      planes.where((p) => p.type == PlaneType.horizontal).length;
}

/// Сервис AR-сканирования.
///
/// - iOS: использует ARKit (через arkit_plugin); плоскости приходят напрямую
///   из ARKitSceneView через колбэки в FloorPlanScreen.
/// - Android: использует ARCore через нативный PlatformView + EventChannel.
///   Данные о плоскостях приходят в [onAndroidPlaneEvent].
class ArScanService extends ChangeNotifier {
  final List<DetectedPlane> _planes = [];
  bool _isScanning = false;
  String? _errorMessage;

  // Android ARCore channels — инициализируются при создании view
  EventChannel? _androidPlanesChannel;
  MethodChannel? _androidControlChannel;
  // ignore: cancel_subscriptions
  Stream<dynamic>? _androidPlanesStream;

  List<DetectedPlane> get planes => List.unmodifiable(_planes);
  bool get isScanning => _isScanning;
  String? get errorMessage => _errorMessage;

  /// Поддерживается ли AR-сканирование на текущей платформе.
  bool get isSupported => Platform.isIOS || Platform.isAndroid;

  // ── Управление сканированием ─────────────────────────────────────────────

  void startScan() {
    _planes.clear();
    _isScanning = true;
    _errorMessage = null;
    notifyListeners();

    if (Platform.isAndroid) {
      _androidControlChannel?.invokeMethod('resume');
    }
  }

  void stopScan() {
    _isScanning = false;
    if (Platform.isAndroid) {
      _androidControlChannel?.invokeMethod('pause');
    }
    notifyListeners();
  }

  void reset() {
    _planes.clear();
    _isScanning = false;
    _errorMessage = null;
    if (Platform.isAndroid) {
      _androidControlChannel?.invokeMethod('reset');
    }
    notifyListeners();
  }

  // ── ARKit (iOS) ──────────────────────────────────────────────────────────

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

  // ── ARCore (Android) ─────────────────────────────────────────────────────

  /// Регистрирует каналы для Android ARCore PlatformView с заданным [viewId].
  ///
  /// Вызывается из FloorPlanScreen сразу после создания AndroidView.
  void initAndroidChannels(int viewId) {
    if (!Platform.isAndroid) return;

    _androidPlanesChannel = EventChannel(
      '${ArCoreView.planesChannel}/$viewId',
    );
    _androidControlChannel = MethodChannel(
      '${ArCoreView.controlChannel}/$viewId',
    );

    _androidPlanesStream = _androidPlanesChannel!.receiveBroadcastStream();
    _androidPlanesStream!.listen(
      onAndroidPlaneEvent,
      onError: _onAndroidError,
    );
  }

  /// Обрабатывает событие плоскости от нативной стороны Android.
  void onAndroidPlaneEvent(dynamic event) {
    if (event is! Map) return;
    final map = Map<String, dynamic>.from(event);

    final id = map['id'] as String? ?? '';
    if (id.isEmpty) return;

    // Удалённая плоскость
    if (map['removed'] == true) {
      removePlane(id);
      return;
    }

    final typeStr = map['type'] as String? ?? 'horizontal';
    final type =
        typeStr == 'vertical' ? PlaneType.vertical : PlaneType.horizontal;

    final extentX = (map['extentX'] as num? ?? 0).toDouble();
    final extentZ = (map['extentZ'] as num? ?? 0).toDouble();
    final cx = (map['centerX'] as num? ?? 0).toDouble();
    final cy = (map['centerY'] as num? ?? 0).toDouble();
    final cz = (map['centerZ'] as num? ?? 0).toDouble();

    final plane = DetectedPlane(
      id: id,
      type: type,
      center: Vector3(cx, cy, cz),
      extent: Vector2(extentX, extentZ),
    );
    updatePlane(plane);
  }

  void _onAndroidError(dynamic error) {
    if (error is PlatformException) {
      setError('ARCore: ${error.message ?? error.code}');
    } else {
      setError('ARCore error');
    }
  }

  // ── Результат ────────────────────────────────────────────────────────────

  ScanResult buildResult() {
    return ScanResult(
      planes: List.from(_planes),
      timestamp: DateTime.now(),
    );
  }

  void setError(String message) {
    _errorMessage = message;
    _isScanning = false;
    notifyListeners();
  }
}

/// Константы имён каналов — синхронизированы с ArCoreView.kt.
class ArCoreView {
  static const planesChannel = 'wardrobe/arcore_planes';
  static const controlChannel = 'wardrobe/arcore_control';
  static const viewType = 'wardrobe/arcore_view';
}
