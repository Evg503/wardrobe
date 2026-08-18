import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart'
    as mlkit;

/// Результат распознавания одного объекта.
class DetectedObject {
  final String label;
  final String category;
  final double confidence;

  /// Нормализованные координаты bounding box (0.0 – 1.0 от размера кадра).
  final Rect boundingBox;

  const DetectedObject({
    required this.label,
    required this.category,
    required this.confidence,
    required this.boundingBox,
  });
}

/// Сервис распознавания объектов через Google ML Kit.
///
/// Использует встроенную базовую модель ML Kit (без кастомного tflite).
/// Детектор работает в режиме [DetectionMode.single] — анализ по запросу.
class ObjectDetectionService extends ChangeNotifier {
  mlkit.ObjectDetector? _detector;
  bool _isProcessing = false;
  List<DetectedObject> _results = [];
  String? _errorMessage;

  List<DetectedObject> get results => _results;
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;

  /// Инициализирует детектор ML Kit.
  void initialize() {
    final options = mlkit.ObjectDetectorOptions(
      mode: mlkit.DetectionMode.single,
      classifyObjects: true,
      multipleObjects: true,
    );
    _detector = mlkit.ObjectDetector(options: options);
  }

  /// Анализирует кадр с камеры в потоке (imageStream).
  Future<void> processFrame(
    CameraImage image,
    int sensorOrientation,
    CameraLensDirection lensDirection,
  ) async {
    if (_isProcessing || _detector == null) return;
    _isProcessing = true;

    try {
      final inputImage = _toInputImage(image, sensorOrientation, lensDirection);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      final objects = await _detector!.processImage(inputImage);
      _results = _mapResults(objects, image.width, image.height);
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Ошибка распознавания: $e';
      debugPrint(_errorMessage);
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Анализирует изображение из файла (например, после `takePicture`).
  Future<List<DetectedObject>> processFile(String imagePath) async {
    if (_detector == null) return [];
    try {
      final inputImage = mlkit.InputImage.fromFilePath(imagePath);
      final objects = await _detector!.processImage(inputImage);
      return _mapResults(objects, 0, 0);
    } catch (e) {
      debugPrint('Ошибка обработки файла: $e');
      return [];
    }
  }

  void clearResults() {
    _results = [];
    notifyListeners();
  }

  // ── Приватные методы ────────────────────────────────────────────────────

  mlkit.InputImage? _toInputImage(
    CameraImage image,
    int sensorOrientation,
    CameraLensDirection lensDirection,
  ) {
    final format = mlkit.InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final rotation = _sensorToRotation(sensorOrientation, lensDirection);

    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final metadata = mlkit.InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return mlkit.InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  mlkit.InputImageRotation _sensorToRotation(
    int sensorOrientation,
    CameraLensDirection lensDirection,
  ) {
    // Передняя камера на Android зеркалится — инвертируем поворот
    if (lensDirection == CameraLensDirection.front) {
      switch (sensorOrientation) {
        case 90:
          return mlkit.InputImageRotation.rotation270deg;
        case 270:
          return mlkit.InputImageRotation.rotation90deg;
      }
    }
    switch (sensorOrientation) {
      case 90:
        return mlkit.InputImageRotation.rotation90deg;
      case 180:
        return mlkit.InputImageRotation.rotation180deg;
      case 270:
        return mlkit.InputImageRotation.rotation270deg;
      default:
        return mlkit.InputImageRotation.rotation0deg;
    }
  }

  List<DetectedObject> _mapResults(
    List<mlkit.DetectedObject> objects,
    int imageWidth,
    int imageHeight,
  ) {
    final result = <DetectedObject>[];
    for (final obj in objects) {
      if (obj.labels.isEmpty) continue;

      final best = obj.labels.reduce(
        (a, b) => a.confidence > b.confidence ? a : b,
      );
      if (best.confidence < 0.4) continue;

      Rect normalized = Rect.zero;
      if (imageWidth > 0 && imageHeight > 0) {
        final box = obj.boundingBox;
        normalized = Rect.fromLTRB(
          (box.left / imageWidth).clamp(0.0, 1.0),
          (box.top / imageHeight).clamp(0.0, 1.0),
          (box.right / imageWidth).clamp(0.0, 1.0),
          (box.bottom / imageHeight).clamp(0.0, 1.0),
        );
      }

      result.add(DetectedObject(
        label: _localizeLabel(best.text),
        category: _categoryFromLabel(best.text),
        confidence: best.confidence,
        boundingBox: normalized,
      ));
    }
    return result;
  }

  String _localizeLabel(String raw) {
    const map = {
      'Sofa': 'Диван',
      'Couch': 'Диван',
      'Chair': 'Кресло',
      'Armchair': 'Кресло',
      'Table': 'Стол',
      'Coffee table': 'Журнальный стол',
      'Dining table': 'Обеденный стол',
      'Bed': 'Кровать',
      'Desk': 'Письменный стол',
      'Shelf': 'Полка',
      'Lamp': 'Лампа',
      'Floor lamp': 'Торшер',
      'Cabinet': 'Шкаф',
      'Wardrobe': 'Шкаф-купе',
      'Bookcase': 'Книжный шкаф',
      'Dresser': 'Комод',
      'Plant': 'Растение',
      'Houseplant': 'Комнатное растение',
      'Rug': 'Ковёр',
      'Carpet': 'Ковёр',
      'Picture frame': 'Картина',
      'Mirror': 'Зеркало',
      'Television': 'Телевизор',
      'TV': 'Телевизор',
      'Computer': 'Компьютер',
      'Laptop': 'Ноутбук',
      'Refrigerator': 'Холодильник',
      'Washing machine': 'Стиральная машина',
      'Furniture': 'Мебель',
      'Home appliance': 'Бытовая техника',
      'Person': 'Человек',
    };
    return map[raw] ?? raw;
  }

  String _categoryFromLabel(String raw) {
    const furniture = {
      'Sofa', 'Couch', 'Chair', 'Armchair', 'Table',
      'Coffee table', 'Dining table', 'Bed', 'Desk', 'Shelf',
      'Cabinet', 'Wardrobe', 'Bookcase', 'Dresser', 'Furniture',
    };
    const lighting = {'Lamp', 'Floor lamp'};
    const textile = {'Rug', 'Carpet'};
    const decor = {'Picture frame', 'Mirror', 'Plant', 'Houseplant'};
    const electronics = {'Television', 'TV', 'Computer', 'Laptop'};
    const appliances = {
      'Refrigerator', 'Washing machine', 'Home appliance',
    };

    if (furniture.contains(raw)) return 'Мебель';
    if (lighting.contains(raw)) return 'Освещение';
    if (textile.contains(raw)) return 'Текстиль';
    if (decor.contains(raw)) return 'Декор';
    if (electronics.contains(raw)) return 'Электроника';
    if (appliances.contains(raw)) return 'Техника';
    return 'Предмет';
  }

  @override
  void dispose() {
    _detector?.close();
    super.dispose();
  }
}
