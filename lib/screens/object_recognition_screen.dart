import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../services/camera_service.dart';
import '../services/object_detection_service.dart';
import '../theme/app_theme.dart';
import '../widgets/camera_preview_widget.dart';

class ObjectRecognitionScreen extends StatefulWidget {
  const ObjectRecognitionScreen({super.key});

  @override
  State<ObjectRecognitionScreen> createState() =>
      _ObjectRecognitionScreenState();
}

class _ObjectRecognitionScreenState extends State<ObjectRecognitionScreen>
    with SingleTickerProviderStateMixin {
  late final CameraService _cameraService;
  late final ObjectDetectionService _detectionService;
  late AnimationController _scanLineController;
  late Animation<double> _scanLineAnimation;

  bool _isStreaming = false;

  @override
  void initState() {
    super.initState();

    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _scanLineAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );

    _cameraService = CameraService();
    _detectionService = ObjectDetectionService();

    _detectionService.addListener(_onDetectionUpdate);
    _detectionService.initialize(DetectorMode.custom);
    _cameraService.addListener(_onCameraUpdate);
    _cameraService.initialize();
  }

  void _onCameraUpdate() {
    if (mounted) setState(() {});
  }

  void _onDetectionUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // stopStream без await — dispose не может быть async
    _isStreaming = false;
    try { _cameraService.controller?.stopImageStream(); } catch (_) {}
    _scanLineController.dispose();
    _detectionService.removeListener(_onDetectionUpdate);
    _detectionService.dispose();
    _cameraService.removeListener(_onCameraUpdate);
    _cameraService.dispose();
    super.dispose();
  }

  // ── Управление ──────────────────────────────────────────────────────────

  void _startRecognition() {
    if (!_cameraService.isInitialized) return;
    _detectionService.clearResults();
    _startStream();
  }

  void _startStream() {
    final controller = _cameraService.controller;
    if (controller == null || _isStreaming) return;

    setState(() => _isStreaming = true);

    controller.startImageStream((CameraImage image) {
      final desc = controller.description;
      _detectionService.processFrame(
        image,
        desc.sensorOrientation,
        desc.lensDirection,
      );
    });
  }

  Future<void> _stopStream() async {
    if (!_isStreaming) return;
    _isStreaming = false;
    try {
      _cameraService.controller?.stopImageStream();
    } catch (_) {}

    // Сохраняем сессию если есть результаты
    final results = _detectionService.results;
    if (results.isNotEmpty && mounted) {
      await AppStateScope.of(context).onRecognitionFinished(results);
    }
    if (mounted) setState(() {});
  }

  void _clearResults() {
    _stopStream();
    _detectionService.clearResults();
    setState(() {});
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final objects = _detectionService.results;
    final isRecognizing = _isStreaming || _detectionService.isProcessing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Распознавание предметов'),
        actions: [
          // Переключатель модели
          _ModelToggle(
            mode: _detectionService.mode,
            onChanged: (mode) async {
              if (_isStreaming) await _stopStream();
              await _detectionService.switchMode(mode);
            },
          ),
          if (objects.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Очистить',
              onPressed: _clearResults,
            ),
          if (_isStreaming)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Остановить',
              onPressed: _stopStream,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Видоискатель с реальной камерой
            Expanded(
              flex: 5,
              child: _CameraView(
                cameraService: _cameraService,
                objects: objects,
                isRecognizing: isRecognizing,
                scanLineAnimation: _scanLineAnimation,
              ),
            ),
            // Панель результатов
            Expanded(
              flex: 4,
              child: _ResultsPanel(
                objects: objects,
                isRecognizing: isRecognizing,
                onStart: _startRecognition,
                errorMessage: _detectionService.errorMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Видоискатель ─────────────────────────────────────────────────────────────

class _CameraView extends StatelessWidget {
  final CameraService cameraService;
  final List<DetectedObject> objects;
  final bool isRecognizing;
  final Animation<double> scanLineAnimation;

  const _CameraView({
    required this.cameraService,
    required this.objects,
    required this.isRecognizing,
    required this.scanLineAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: CameraPreviewWidget(
        cameraService: cameraService,
        overlays: [
          // Нормализованные bounding-боксы поверх реального видео
          if (objects.isNotEmpty)
            _BoundingBoxOverlay(objects: objects),

          // Линия сканирования
          if (isRecognizing)
            AnimatedBuilder(
              animation: scanLineAnimation,
              builder: (context, _) {
                return Positioned(
                  top: scanLineAnimation.value * 200,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppTheme.secondary.withValues(alpha: 0.8),
                          AppTheme.secondary,
                          AppTheme.secondary.withValues(alpha: 0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

          // Подсказка в состоянии ожидания
          if (!isRecognizing && objects.isEmpty)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Нажмите "Распознать"',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),

          // Счётчик объектов
          if (objects.isNotEmpty)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${objects.length} объект${_plural(objects.length)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _plural(int n) {
    if (n == 1) return '';
    if (n >= 2 && n <= 4) return 'а';
    return 'ов';
  }
}

/// Рисует bounding-боксы поверх видеопотока используя нормализованные координаты.
class _BoundingBoxOverlay extends StatelessWidget {
  final List<DetectedObject> objects;

  const _BoundingBoxOverlay({required this.objects});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: objects.map((obj) {
            if (obj.boundingBox == Rect.zero) return const SizedBox.shrink();
            final box = obj.boundingBox;
            return Positioned(
              left: box.left * constraints.maxWidth,
              top: box.top * constraints.maxHeight,
              width: box.width * constraints.maxWidth,
              height: box.height * constraints.maxHeight,
              child: _BoundingBox(
                label: obj.label,
                confidence: obj.confidence,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _BoundingBox extends StatelessWidget {
  final String label;
  final double confidence;

  const _BoundingBox({required this.label, required this.confidence});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.secondary, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.secondary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$label ${(confidence * 100).round()}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Панель результатов ────────────────────────────────────────────────────────

class _ResultsPanel extends StatelessWidget {
  final List<DetectedObject> objects;
  final bool isRecognizing;
  final VoidCallback onStart;
  final String? errorMessage;

  const _ResultsPanel({
    required this.objects,
    required this.isRecognizing,
    required this.onStart,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  objects.isEmpty
                      ? 'Готово к распознаванию'
                      : 'Найденные объекты',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                ),
                ElevatedButton.icon(
                  onPressed: isRecognizing ? null : onStart,
                  icon: isRecognizing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search, size: 18),
                  label: Text(isRecognizing ? 'Анализ...' : 'Распознать'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            errorMessage!,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.red.shade400),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (objects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            isRecognizing
                ? 'Анализируем предметы в кадре...'
                : 'Направьте камеру на предмет\nи нажмите "Распознать"',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.6,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: objects.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _ObjectTile(object: objects[index]),
    );
  }
}

class _ObjectTile extends StatelessWidget {
  final DetectedObject object;

  const _ObjectTile({required this.object});

  @override
  Widget build(BuildContext context) {
    final color = _colorForCategory(object.category);
    final icon = _iconForCategory(object.category);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  object.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                  ),
                ),
                Text(
                  object.category,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(object.confidence * 100).round()}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 60,
                child: LinearProgressIndicator(
                  value: object.confidence,
                  backgroundColor: Colors.grey.shade200,
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _colorForCategory(String category) {
    switch (category) {
      case 'Мебель':
        return const Color(0xFF2D4A3E);
      case 'Освещение':
        return const Color(0xFF5C3D1A);
      case 'Текстиль':
        return const Color(0xFF3D1A5C);
      case 'Декор':
        return const Color(0xFF1A5C3D);
      case 'Электроника':
        return const Color(0xFF1A3A5C);
      case 'Техника':
        return const Color(0xFF5C1A1A);
      default:
        return Colors.grey.shade600;
    }
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'Мебель':
        return Icons.chair_outlined;
      case 'Освещение':
        return Icons.light_outlined;
      case 'Текстиль':
        return Icons.texture;
      case 'Декор':
        return Icons.photo_outlined;
      case 'Электроника':
        return Icons.devices_outlined;
      case 'Техника':
        return Icons.kitchen_outlined;
      default:
        return Icons.category_outlined;
    }
  }
}

// ── Переключатель модели ──────────────────────────────────────────────────────

class _ModelToggle extends StatelessWidget {
  final DetectorMode mode;
  final Future<void> Function(DetectorMode) onChanged;

  const _ModelToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isCustom = mode == DetectorMode.custom;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Tooltip(
        message: isCustom
            ? 'Режим: EfficientDet-Lite (мебель)\nНажмите для базовой модели'
            : 'Режим: базовая ML Kit\nНажмите для EfficientDet-Lite',
        child: GestureDetector(
          onTap: () => onChanged(
            isCustom ? DetectorMode.base : DetectorMode.custom,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isCustom
                  ? AppTheme.secondary.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isCustom
                    ? AppTheme.secondary.withValues(alpha: 0.5)
                    : Colors.grey.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isCustom ? Icons.auto_awesome : Icons.smart_toy_outlined,
                  size: 14,
                  color: isCustom ? AppTheme.primary : Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  isCustom ? 'EfficientDet' : 'Base',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color:
                        isCustom ? AppTheme.primary : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
