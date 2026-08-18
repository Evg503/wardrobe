import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/camera_service.dart';
import '../theme/app_theme.dart';

/// Виджет превью камеры с кнопками управления.
/// Показывает реальный видеопоток; поверх можно добавить произвольные оверлеи через [overlays].
class CameraPreviewWidget extends StatefulWidget {
  /// Дочерние виджеты-оверлеи поверх видеопотока (например, bounding-боксы).
  final List<Widget> overlays;

  /// Показывать ли кнопки переключения камеры и вспышки.
  final bool showControls;

  const CameraPreviewWidget({
    super.key,
    this.overlays = const [],
    this.showControls = true,
  });

  @override
  State<CameraPreviewWidget> createState() => _CameraPreviewWidgetState();
}

class _CameraPreviewWidgetState extends State<CameraPreviewWidget> {
  late final CameraService _cameraService;

  @override
  void initState() {
    super.initState();
    _cameraService = CameraService();
    _cameraService.addListener(_onCameraUpdate);
    _cameraService.initialize();
  }

  void _onCameraUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cameraService.removeListener(_onCameraUpdate);
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Видеопоток или заглушка
          _buildCameraBody(),

          // Пользовательские оверлеи
          ...widget.overlays,

          // Кнопки управления камерой
          if (widget.showControls) _buildControls(),
        ],
      ),
    );
  }

  Widget _buildCameraBody() {
    if (_cameraService.errorMessage != null) {
      return _ErrorPlaceholder(message: _cameraService.errorMessage!);
    }

    if (!_cameraService.isInitialized || _cameraService.controller == null) {
      return const _LoadingPlaceholder();
    }

    final controller = _cameraService.controller!;

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.previewSize?.height ?? 1,
        height: controller.value.previewSize?.width ?? 1,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildControls() {
    return Positioned(
      top: 12,
      right: 12,
      child: Column(
        children: [
          // Переключение камеры
          if (_cameraService.hasMultipleCameras)
            _ControlButton(
              icon: Icons.flip_camera_ios_outlined,
              onTap: _cameraService.switchCamera,
              tooltip: 'Переключить камеру',
            ),
          const SizedBox(height: 8),
          // Вспышка
          _ControlButton(
            icon: _flashIcon(_cameraService.flashMode),
            onTap: _cameraService.toggleFlash,
            tooltip: 'Вспышка',
            active: _cameraService.flashMode != FlashMode.off,
          ),
        ],
      ),
    );
  }

  IconData _flashIcon(FlashMode mode) {
    switch (mode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      default:
        return Icons.flash_off;
    }
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool active;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active
                ? AppTheme.secondary.withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: const Center(
        child: CircularProgressIndicator(color: AppTheme.secondary),
      ),
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  final String message;

  const _ErrorPlaceholder({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt_outlined,
                  size: 48, color: Colors.white38),
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
