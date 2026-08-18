import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Сервис для управления камерой.
/// Инкапсулирует инициализацию, переключение камер и управление вспышкой.
class CameraService extends ChangeNotifier {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isInitialized = false;
  String? _errorMessage;
  FlashMode _flashMode = FlashMode.off;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  FlashMode get flashMode => _flashMode;
  bool get hasMultipleCameras => _cameras.length > 1;

  /// Возвращает true если текущая камера — задняя
  bool get isBackCamera =>
      _cameras.isNotEmpty &&
      _cameras[_selectedCameraIndex].lensDirection ==
          CameraLensDirection.back;

  /// Инициализирует список камер и запускает заднюю камеру по умолчанию.
  Future<void> initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _errorMessage = 'Камера не найдена на устройстве';
        notifyListeners();
        return;
      }
      // Предпочитаем заднюю камеру
      _selectedCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (_selectedCameraIndex < 0) _selectedCameraIndex = 0;

      await _startCamera(_cameras[_selectedCameraIndex]);
    } catch (e) {
      _errorMessage = 'Ошибка инициализации камеры: $e';
      notifyListeners();
    }
  }

  Future<void> _startCamera(CameraDescription description) async {
    // Освобождаем предыдущий контроллер
    await _disposeController();

    _controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _controller!.initialize();
      await _controller!.setFlashMode(_flashMode);
      _isInitialized = true;
      _errorMessage = null;
    } catch (e) {
      _isInitialized = false;
      _errorMessage = 'Не удалось запустить камеру: $e';
    }
    notifyListeners();
  }

  /// Переключает между передней и задней камерой.
  Future<void> switchCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    _isInitialized = false;
    notifyListeners();
    await _startCamera(_cameras[_selectedCameraIndex]);
  }

  /// Переключает режим вспышки: выкл → авто → вкл → выкл.
  Future<void> toggleFlash() async {
    if (_controller == null || !_isInitialized) return;

    final modes = [FlashMode.off, FlashMode.auto, FlashMode.always];
    final nextIndex = (modes.indexOf(_flashMode) + 1) % modes.length;
    _flashMode = modes[nextIndex];

    try {
      await _controller!.setFlashMode(_flashMode);
    } catch (_) {
      // Некоторые устройства не поддерживают все режимы — игнорируем
    }
    notifyListeners();
  }

  /// Делает снимок и возвращает путь к файлу.
  Future<XFile?> takePicture() async {
    if (_controller == null || !_isInitialized) return null;
    try {
      return await _controller!.takePicture();
    } catch (e) {
      debugPrint('Ошибка съёмки: $e');
      return null;
    }
  }

  Future<void> _disposeController() async {
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }
    _isInitialized = false;
  }

  @override
  Future<void> dispose() async {
    await _disposeController();
    super.dispose();
  }
}
