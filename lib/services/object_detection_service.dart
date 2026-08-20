import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart'
    as mlkit;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Режим работы детектора.
enum DetectorMode {
  /// Встроенная базовая модель ML Kit — быстрый запуск, широкие категории.
  base,

  /// Кастомная TFLite-модель EfficientDet-Lite0 (COCO 80 классов) —
  /// конкретные предметы: chair, couch, bed, dining table, laptop, tv и др.
  custom,
}

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
/// Поддерживает два режима через [DetectorMode]:
/// - [DetectorMode.base] — встроенная модель ML Kit, ~5 категорий
/// - [DetectorMode.custom] — EfficientDet-Lite0 (COCO 80 классов),
///   конкретные предметы интерьера
///
/// Переключение режима через [switchMode] — пересоздаёт детектор.
class ObjectDetectionService extends ChangeNotifier {
  static const _modelAsset = 'assets/ml/furniture_detector.tflite';

  mlkit.ObjectDetector? _detector;
  bool _isProcessing = false;
  List<DetectedObject> _results = [];
  String? _errorMessage;
  DetectorMode _mode = DetectorMode.custom;
  bool _isInitialized = false;

  List<DetectedObject> get results => _results;
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;
  DetectorMode get mode => _mode;
  bool get isInitialized => _isInitialized;

  // ── Инициализация ────────────────────────────────────────────────────────

  /// Инициализирует детектор в режиме [mode] (по умолчанию custom).
  Future<void> initialize([DetectorMode mode = DetectorMode.custom]) async {
    _mode = mode;
    await _createDetector();
  }

  /// Переключает режим и пересоздаёт детектор.
  Future<void> switchMode(DetectorMode mode) async {
    if (_mode == mode && _isInitialized) return;
    _mode = mode;
    _results = [];
    _errorMessage = null;
    _isInitialized = false;
    notifyListeners();
    await _createDetector();
  }

  Future<void> _createDetector() async {
    _detector?.close();
    _detector = null;

    try {
      if (_mode == DetectorMode.custom) {
        final modelPath = await _copyAssetToLocal(_modelAsset);
        final options = mlkit.LocalObjectDetectorOptions(
          mode: mlkit.DetectionMode.stream,
          modelPath: modelPath,
          classifyObjects: true,
          multipleObjects: true,
          confidenceThreshold: 0.45,
        );
        _detector = mlkit.ObjectDetector(options: options);
      } else {
        final options = mlkit.ObjectDetectorOptions(
          mode: mlkit.DetectionMode.stream,
          classifyObjects: true,
          multipleObjects: true,
        );
        _detector = mlkit.ObjectDetector(options: options);
      }
      _isInitialized = true;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Ошибка инициализации детектора: $e';
      debugPrint(_errorMessage);
    }
    notifyListeners();
  }

  /// Копирует asset во временную директорию (ML Kit требует путь к файлу).
  Future<String> _copyAssetToLocal(String assetPath) async {
    final dir = await getTemporaryDirectory();
    final fileName = p.basename(assetPath);
    final file = File(p.join(dir.path, fileName));

    if (!await file.exists()) {
      final data = await rootBundle.load(assetPath);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }
    return file.path;
  }

  // ── Обработка кадров ─────────────────────────────────────────────────────

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
    } on Exception catch (e) {
      // Если NV21 падает с PlatformException — пробуем переключиться на base
      if (_mode == DetectorMode.custom &&
          e.toString().contains('InputImageConvert')) {
        debugPrint('Switching to base mode after NV21 conversion failure');
        _mode = DetectorMode.base;
        await _createDetector();
        return;
      }
      _errorMessage = 'Ошибка распознавания: $e';
      debugPrint(_errorMessage);
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Анализирует изображение из файла.
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

  // ── Приватные методы ─────────────────────────────────────────────────────

  mlkit.InputImage? _toInputImage(
    CameraImage image,
    int sensorOrientation,
    CameraLensDirection lensDirection,
  ) {
    final rotation = _sensorToRotation(sensorOrientation, lensDirection);

    // Android: camera плагин отдаёт YUV_420_888 (три отдельных плейна).
    // Конвертируем YUV_420_888 → NV21 вручную для ML Kit.
    if (Platform.isAndroid) {
      return _toInputImageAndroid(image, rotation);
    }

    // iOS: BGRA8888 — один плейн, прямая передача.
    final format = mlkit.InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final bytes = image.planes.first.bytes;
    final metadata = mlkit.InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );
    return mlkit.InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  /// Конвертирует YUV_420_888 (Android) в NV21 для ML Kit.
  ///
  /// NV21: Y-плейн (width × height), затем чередующиеся VU (width/2 × height/2 × 2).
  ///
  /// Защитные меры:
  /// - проверяем наличие всех трёх плейнов и непустые bytes
  /// - bytesPerPixel для UV берём из реального значения, fallback = 1
  /// - clamp uvOffset чтобы не выйти за пределы буфера
  mlkit.InputImage? _toInputImageAndroid(
    CameraImage image,
    mlkit.InputImageRotation rotation,
  ) {
    try {
      // Защита: нужны ровно 3 плейна с непустыми данными
      if (image.planes.length < 3) return null;

      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      if (yPlane.bytes.isEmpty || uPlane.bytes.isEmpty || vPlane.bytes.isEmpty) {
        return null;
      }

      final int width = image.width;
      final int height = image.height;
      final int yRowStride = yPlane.bytesPerRow;
      final int uvRowStride = uPlane.bytesPerRow;
      // bytesPerPixel может быть null на некоторых устройствах
      final int uvPixelStride = uPlane.bytesPerPixel ?? 2;

      final int nv21Size = width * height + (width ~/ 2) * (height ~/ 2) * 2;
      final nv21 = Uint8List(nv21Size);

      // Y-плейн: копируем построчно с учётом stride (убираем padding)
      int idx = 0;
      for (int row = 0; row < height; row++) {
        final rowStart = row * yRowStride;
        final rowEnd = rowStart + width;
        if (rowEnd <= yPlane.bytes.length) {
          nv21.setRange(idx, idx + width, yPlane.bytes, rowStart);
        }
        idx += width;
      }

      // VU interleaved: для каждого UV-пикселя записываем V затем U
      final int uvHeight = height ~/ 2;
      final int uvWidth = width ~/ 2;
      for (int row = 0; row < uvHeight; row++) {
        for (int col = 0; col < uvWidth; col++) {
          final int uvOffset = row * uvRowStride + col * uvPixelStride;
          // Защита от выхода за пределы буфера
          final int vByte = uvOffset < vPlane.bytes.length
              ? vPlane.bytes[uvOffset]
              : 128;
          final int uByte = uvOffset < uPlane.bytes.length
              ? uPlane.bytes[uvOffset]
              : 128;
          nv21[idx++] = vByte;
          nv21[idx++] = uByte;
        }
      }

      final metadata = mlkit.InputImageMetadata(
        size: Size(width.toDouble(), height.toDouble()),
        rotation: rotation,
        format: mlkit.InputImageFormat.nv21,
        bytesPerRow: width,
      );
      return mlkit.InputImage.fromBytes(bytes: nv21, metadata: metadata);
    } catch (e) {
      debugPrint('YUV→NV21 conversion error: $e');
      return null;
    }
  }

  mlkit.InputImageRotation _sensorToRotation(
    int sensorOrientation,
    CameraLensDirection lensDirection,
  ) {
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
      // Мебель
      'chair': 'Стул',
      'Chair': 'Стул',
      'couch': 'Диван',
      'Couch': 'Диван',
      'Sofa': 'Диван',
      'sofa': 'Диван',
      'bed': 'Кровать',
      'Bed': 'Кровать',
      'dining table': 'Обеденный стол',
      'Dining table': 'Обеденный стол',
      'Table': 'Стол',
      'table': 'Стол',
      'Coffee table': 'Журнальный стол',
      'Armchair': 'Кресло',
      'Desk': 'Письменный стол',
      'desk': 'Письменный стол',
      'bench': 'Скамья',
      'Bench': 'Скамья',
      'Cabinet': 'Шкаф',
      'Wardrobe': 'Шкаф-купе',
      'Bookcase': 'Книжный шкаф',
      'Dresser': 'Комод',
      'Shelf': 'Полка',
      // Техника
      'tv': 'Телевизор',
      'TV': 'Телевизор',
      'Television': 'Телевизор',
      'laptop': 'Ноутбук',
      'Laptop': 'Ноутбук',
      'refrigerator': 'Холодильник',
      'Refrigerator': 'Холодильник',
      'oven': 'Духовка',
      'Oven': 'Духовка',
      'microwave': 'Микроволновка',
      'Microwave': 'Микроволновка',
      'toaster': 'Тостер',
      'sink': 'Раковина',
      'Sink': 'Раковина',
      'toilet': 'Унитаз',
      'Toilet': 'Унитаз',
      'Washing machine': 'Стиральная машина',
      'mouse': 'Мышь',
      'keyboard': 'Клавиатура',
      'cell phone': 'Телефон',
      'remote': 'Пульт',
      // Декор
      'potted plant': 'Растение',
      'Plant': 'Растение',
      'Houseplant': 'Комнатное растение',
      'vase': 'Ваза',
      'Vase': 'Ваза',
      'clock': 'Часы',
      'Clock': 'Часы',
      'book': 'Книга',
      'Book': 'Книга',
      'Rug': 'Ковёр',
      'Carpet': 'Ковёр',
      'Picture frame': 'Картина',
      'Mirror': 'Зеркало',
      // Освещение
      'Lamp': 'Лампа',
      'Floor lamp': 'Торшер',
      // Прочее
      'person': 'Человек',
      'Person': 'Человек',
      'Furniture': 'Мебель',
      'Home appliance': 'Бытовая техника',
      'scissors': 'Ножницы',
      'bottle': 'Бутылка',
      'cup': 'Чашка',
      'bowl': 'Миска',
      'teddy bear': 'Игрушка',
      'backpack': 'Рюкзак',
      'suitcase': 'Чемодан',
      'umbrella': 'Зонт',
      'handbag': 'Сумка',
    };
    return map[raw] ?? _capitalize(raw);
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _categoryFromLabel(String raw) {
    const furniture = {
      'chair', 'couch', 'bed', 'dining table', 'bench', 'desk',
      'Sofa', 'Couch', 'Chair', 'Armchair', 'Table', 'Coffee table',
      'Dining table', 'Bed', 'Desk', 'Shelf', 'Cabinet', 'Wardrobe',
      'Bookcase', 'Dresser', 'Furniture',
    };
    const lighting = {'Lamp', 'Floor lamp'};
    const textile = {'Rug', 'Carpet'};
    const decor = {
      'potted plant', 'vase', 'clock', 'book', 'teddy bear',
      'Picture frame', 'Mirror', 'Plant', 'Houseplant', 'Vase',
      'Clock', 'Book',
    };
    const electronics = {
      'tv', 'laptop', 'mouse', 'keyboard', 'cell phone', 'remote',
      'Television', 'TV', 'Laptop', 'Computer',
    };
    const appliances = {
      'refrigerator', 'oven', 'microwave', 'toaster', 'sink', 'toilet',
      'Refrigerator', 'Washing machine', 'Home appliance', 'Sink',
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
