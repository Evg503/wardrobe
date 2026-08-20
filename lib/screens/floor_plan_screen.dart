import 'dart:io';

import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

import '../services/app_state.dart';
import '../services/ar_scan_service.dart';
import '../services/export_service.dart';
import '../theme/app_theme.dart';

class FloorPlanScreen extends StatefulWidget {
  const FloorPlanScreen({super.key});

  @override
  State<FloorPlanScreen> createState() => _FloorPlanScreenState();
}

class _FloorPlanScreenState extends State<FloorPlanScreen> {
  final ArScanService _scanService = ArScanService();
  final GlobalKey _planRepaintKey = GlobalKey();
  bool _hasPlan = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _scanService.addListener(_onScanUpdate);
  }

  void _onScanUpdate() {
    if (!mounted) return;
    // Показываем ошибку ARCore через SnackBar если она появилась
    final err = _scanService.errorMessage;
    if (err != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showSnackBar(context, err);
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    _scanService.removeListener(_onScanUpdate);
    _scanService.dispose();
    super.dispose();
  }

  void _startScan() {
    setState(() => _hasPlan = false);
    _scanService.startScan();
  }

  Future<void> _stopScan() async {
    _scanService.stopScan();
    final result = _scanService.buildResult();
    if (result.planes.isNotEmpty && mounted) {
      await AppStateScope.of(context).onScanFinished(result);
      setState(() => _hasPlan = true);
    }
  }

  void _resetScan() {
    _scanService.reset();
    setState(() => _hasPlan = false);
  }

  // ── Экспорт ───────────────────────────────────────────────────────────────

  Future<void> _showExportSheet({bool share = false}) async {
    final format = await showModalBottomSheet<ExportFormat>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ExportFormatSheet(share: share),
    );
    if (format == null || !mounted) return;
    await _doExport(format, share: share);
  }

  Future<void> _doExport(ExportFormat format, {required bool share}) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      ExportResult result;
      if (format == ExportFormat.png) {
        result = await ExportService.exportPng(_planRepaintKey);
      } else {
        result = await ExportService.exportPdf(_scanService.buildResult());
      }
      if (share) {
        await ExportService.share(result, subject: 'План квартиры');
      } else {
        if (mounted) {
          _showSnackBar(
            context,
            'Сохранено: ${result.path.split('/').last}',
          );
        }
      }
    } catch (e) {
      if (mounted) _showSnackBar(context, 'Ошибка экспорта: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isScanning = _scanService.isScanning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('План квартиры'),
        actions: [
          if (_hasPlan) ...[
            if (_exporting)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'Поделиться',
                onPressed: () => _showExportSheet(share: true),
              ),
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Сохранить',
                onPressed: () => _showExportSheet(share: false),
              ),
            ],
          ],
          if (isScanning)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Завершить сканирование',
              onPressed: _stopScan,
            ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(isScanning),
      ),
    );
  }

  Widget _buildBody(bool isScanning) {
    if (_hasPlan) {
      return _PlanView(
        scanService: _scanService,
        onRescan: _resetScan,
        onSave: () => _showExportSheet(share: false),
        planRepaintKey: _planRepaintKey,
      );
    }
    if (isScanning) {
      return _ScanningView(scanService: _scanService, onStop: _stopScan);
    }
    return _EmptyView(
      onStart: _startScan,
      errorMessage: _scanService.errorMessage,
    );
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

// ── Bottomsheet выбора формата ────────────────────────────────────────────────

class _ExportFormatSheet extends StatelessWidget {
  final bool share;
  const _ExportFormatSheet({required this.share});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            share ? 'Поделиться как...' : 'Сохранить как...',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _FormatTile(
            icon: Icons.image_outlined,
            title: 'PNG',
            subtitle: 'Растровое изображение плана (высокое качество)',
            onTap: () => Navigator.pop(context, ExportFormat.png),
          ),
          const SizedBox(height: 8),
          _FormatTile(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF',
            subtitle: 'Документ с векторным планом и статистикой',
            onTap: () => Navigator.pop(context, ExportFormat.pdf),
          ),
        ],
      ),
    );
  }
}

class _FormatTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FormatTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.secondary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

// ── Пустой экран ─────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final VoidCallback onStart;
  final String? errorMessage;

  const _EmptyView({required this.onStart, this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.map_outlined, size: 56, color: AppTheme.primary),
          ),
          const SizedBox(height: 32),
          Text(
            'Сканирование комнаты',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Направьте камеру на комнату и медленно обведите\n'
            'пространство. Приложение обнаружит поверхности\n'
            'и построит план.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.6,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (Platform.isIOS) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ARKit активен. Лучший результат на iPhone с LiDAR (12 Pro+)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.green.shade700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ARCore активен. Доступно на устройствах '
                      'с поддержкой ARCore (Android 7.0+).',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.green.shade700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Баннер ошибки ARCore
          if (errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.red.shade700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Начать сканирование'),
          ),
        ],
      ),
    );
  }
}

// ── Экран сканирования ────────────────────────────────────────────────────────

class _ScanningView extends StatefulWidget {
  final ArScanService scanService;
  final VoidCallback onStop;

  const _ScanningView({required this.scanService, required this.onStop});

  @override
  State<_ScanningView> createState() => _ScanningViewState();
}

class _ScanningViewState extends State<_ScanningView> {
  ARKitController? _arkitController;

  @override
  void dispose() {
    _arkitController?.dispose();
    super.dispose();
  }

  void _onARKitViewCreated(ARKitController controller) {
    _arkitController = controller;

    // Слушаем обнаружение плоскостей
    controller.onAddNodeForAnchor = _onAnchorAdded;
    controller.onUpdateNodeForAnchor = _onAnchorUpdated;
    controller.onDidRemoveNodeForAnchor = _onAnchorRemoved;
  }

  void _onAnchorAdded(ARKitAnchor anchor) {
    if (anchor is ARKitPlaneAnchor) {
      _updatePlane(anchor);
      _addPlaneVisualization(anchor);
    }
  }

  void _onAnchorUpdated(ARKitAnchor anchor) {
    if (anchor is ARKitPlaneAnchor) {
      _updatePlane(anchor);
      _arkitController?.remove(anchor.identifier);
      _addPlaneVisualization(anchor);
    }
  }

  void _onAnchorRemoved(ARKitAnchor anchor) {
    widget.scanService.removePlane(anchor.identifier);
  }

  /// Определяем тип плоскости по Y-компоненте нормали из матрицы трансформации.
  /// Горизонтальная плоскость: нормаль смотрит вверх (Y~1).
  PlaneType _planeType(ARKitPlaneAnchor anchor) {
    // Нормаль плоскости — столбец Y матрицы (индексы [1], [5], [9])
    final m = anchor.transform.storage;
    final normalY = m[5].abs(); // Y-компонента вектора вверх
    return normalY > 0.7 ? PlaneType.horizontal : PlaneType.vertical;
  }

  void _updatePlane(ARKitPlaneAnchor anchor) {
    final plane = DetectedPlane(
      id: anchor.identifier,
      type: _planeType(anchor),
      center: vector.Vector3(
        anchor.center.x.toDouble(),
        anchor.center.y.toDouble(),
        anchor.center.z.toDouble(),
      ),
      extent: vector.Vector2(
        anchor.extent.x.toDouble(),
        anchor.extent.z.toDouble(),
      ),
    );
    widget.scanService.updatePlane(plane);
  }

  void _addPlaneVisualization(ARKitPlaneAnchor anchor) {
    final isHorizontal = _planeType(anchor) == PlaneType.horizontal;

    final material = ARKitMaterial(
      diffuse: ARKitMaterialProperty.color(
        isHorizontal
            ? AppTheme.secondary.withValues(alpha: 0.35)
            : AppTheme.primary.withValues(alpha: 0.25),
      ),
      doubleSided: true,
    );

    final plane = ARKitPlane(
      width: anchor.extent.x,
      height: anchor.extent.z,
      materials: [material],
    );

    final node = ARKitNode(
      name: anchor.identifier,
      geometry: plane,
      position: vector.Vector3(
        anchor.center.x.toDouble(),
        anchor.center.y.toDouble(),
        anchor.center.z.toDouble(),
      ),
      eulerAngles: isHorizontal
          ? vector.Vector3(-1.5708, 0, 0) // -90° по X для горизонтальной плоскости
          : vector.Vector3(0, 0, 0),
    );

    _arkitController?.add(node, parentNodeName: anchor.identifier);
  }

  @override
  Widget build(BuildContext context) {
    final planes = widget.scanService.planes;
    final horizontalCount =
        planes.where((p) => p.type == PlaneType.horizontal).length;
    final verticalCount =
        planes.where((p) => p.type == PlaneType.vertical).length;

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              // ARKit-вид (iOS) или ARCore PlatformView (Android)
              if (Platform.isIOS)
                ARKitSceneView(
                  onARKitViewCreated: _onARKitViewCreated,
                  planeDetection: ARPlaneDetection.horizontalAndVertical,
                  showFeaturePoints: true,
                  showWorldOrigin: false,
                )
              else
                _AndroidArCoreView(
                  onViewCreated: (viewId) {
                    widget.scanService.initAndroidChannels(viewId);
                  },
                ),

              // Оверлей со статистикой обнаружения
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: _ScanStats(
                  horizontal: horizontalCount,
                  vertical: verticalCount,
                ),
              ),

              // Угловые маркеры
              ..._buildCornerMarkers(),
            ],
          ),
        ),
        _ScanningFooter(
          planesCount: planes.length,
          onStop: widget.onStop,
        ),
      ],
    );
  }

  List<Widget> _buildCornerMarkers() {
    const color = AppTheme.secondary;
    const size = 24.0;
    const width = 3.0;
    return [
      Positioned(top: 20, left: 20, child: _CornerMark(color: color, size: size, strokeWidth: width, topLeft: true)),
      Positioned(top: 20, right: 20, child: _CornerMark(color: color, size: size, strokeWidth: width, topRight: true)),
      Positioned(bottom: 20, left: 20, child: _CornerMark(color: color, size: size, strokeWidth: width, bottomLeft: true)),
      Positioned(bottom: 20, right: 20, child: _CornerMark(color: color, size: size, strokeWidth: width, bottomRight: true)),
    ];
  }
}

class _ScanStats extends StatelessWidget {
  final int horizontal;
  final int vertical;

  const _ScanStats({required this.horizontal, required this.vertical});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.radar, color: AppTheme.secondary, size: 16),
          const SizedBox(width: 8),
          Text(
            'Полов: $horizontal  |  Стен: $vertical',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ScanningFooter extends StatelessWidget {
  final int planesCount;
  final VoidCallback onStop;

  const _ScanningFooter({required this.planesCount, required this.onStop});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        children: [
          const LinearProgressIndicator(
            backgroundColor: Colors.white24,
            color: AppTheme.secondary,
          ),
          const SizedBox(height: 14),
          Text(
            planesCount == 0
                ? 'Медленно обводите камерой комнату по периметру'
                : 'Обнаружено поверхностей: $planesCount. Продолжайте...',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: planesCount > 0 ? onStop : null,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Завершить'),
          ),
        ],
      ),
    );
  }
}

// ── ARCore View (Android) ─────────────────────────────────────────────────────

/// Встраивает нативный ARCore GLSurfaceView через PlatformView.
/// [onViewCreated] вызывается с viewId сразу после создания виджета.
class _AndroidArCoreView extends StatelessWidget {
  final void Function(int viewId) onViewCreated;

  const _AndroidArCoreView({required this.onViewCreated});

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: ArCoreView.viewType,
      layoutDirection: TextDirection.ltr,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: onViewCreated,
    );
  }
}

// ── Экран результатов ─────────────────────────────────────────────────────────

class _PlanView extends StatelessWidget {
  final ArScanService scanService;
  final VoidCallback onRescan;
  final VoidCallback onSave;
  final GlobalKey planRepaintKey;

  const _PlanView({
    required this.scanService,
    required this.onRescan,
    required this.onSave,
    required this.planRepaintKey,
  });

  @override
  Widget build(BuildContext context) {
    final result = scanService.buildResult();
    final horizontal =
        result.planes.where((p) => p.type == PlaneType.horizontal).toList();
    final vertical =
        result.planes.where((p) => p.type == PlaneType.vertical).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Превью плана — обёрнут в RepaintBoundary для PNG-экспорта
          RepaintBoundary(
            key: planRepaintKey,
            child: Container(
              height: 260,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: CustomPaint(
                  painter: _FloorPlanPainter(
                    horizontal: horizontal,
                    vertical: vertical,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Результаты сканирования',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
          ),
          const SizedBox(height: 12),
          // Статистика по плоскостям
          ...horizontal.asMap().entries.map((e) => _PlaneCard(
                name: 'Горизонтальная поверхность ${e.key + 1}',
                icon: Icons.crop_landscape,
                extent: e.value.extent,
              )),
          ...vertical.asMap().entries.map((e) => _PlaneCard(
                name: 'Стена ${e.key + 1}',
                icon: Icons.crop_portrait,
                extent: e.value.extent,
              )),
          const SizedBox(height: 20),
          // Итоговые цифры
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _TotalStat(
                  'Площадь пола',
                  '${result.totalFloorArea.toStringAsFixed(1)} м²',
                ),
                _VertDivider(),
                _TotalStat('Поверхностей', '${result.planes.length}'),
                _VertDivider(),
                _TotalStat('Стен', '${vertical.length}'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRescan,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Пересканировать'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppTheme.primary),
                    foregroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.download),
                  label: const Text('Сохранить'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlaneCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final vector.Vector2 extent;

  const _PlaneCard({
    required this.name,
    required this.icon,
    required this.extent,
  });

  @override
  Widget build(BuildContext context) {
    final area = extent.x * extent.y;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                Text(
                  '${extent.x.toStringAsFixed(2)} × ${extent.y.toStringAsFixed(2)} м',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '${area.toStringAsFixed(1)} м²',
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
                fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 40, color: AppTheme.primary.withValues(alpha: 0.2));
}

class _TotalStat extends StatelessWidget {
  final String label;
  final String value;

  const _TotalStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }
}

// ── CustomPainter для схемы плана ─────────────────────────────────────────────

class _FloorPlanPainter extends CustomPainter {
  final List<DetectedPlane> horizontal;
  final List<DetectedPlane> vertical;

  const _FloorPlanPainter({required this.horizontal, required this.vertical});

  @override
  void paint(Canvas canvas, Size size) {
    final wallPaint = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = AppTheme.secondary.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    const p = 32.0;
    final w = size.width;
    final h = size.height;

    if (horizontal.isEmpty) {
      // Ещё нет данных — рисуем placeholder
      _drawPlaceholder(canvas, size);
      return;
    }

    // Нормализуем плоскости в пространство canvas
    double maxExtent = horizontal.fold(
      0.0,
      (m, pl) => m < pl.extent.x ? pl.extent.x : m,
    );
    if (maxExtent == 0) maxExtent = 5.0;
    final scale = (w - 2 * p) / maxExtent;

    double offsetY = p;
    for (final plane in horizontal) {
      final pw = plane.extent.x * scale;
      final ph = plane.extent.y * scale;
      final rect = Rect.fromLTWH(p, offsetY, pw, ph.clamp(40.0, h - 2 * p));
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, wallPaint);
      offsetY += rect.height + 12;
      if (offsetY > h - p) break;
    }
  }

  void _drawPlaceholder(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(32, 32, size.width - 64, size.height - 64), paint);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Нет данных сканирования',
        style: TextStyle(color: Colors.grey, fontSize: 13),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_FloorPlanPainter old) =>
      old.horizontal.length != horizontal.length ||
      old.vertical.length != vertical.length;
}

// ── CornerMark ────────────────────────────────────────────────────────────────

class _CornerMark extends StatelessWidget {
  final Color color;
  final double size;
  final double strokeWidth;
  final bool topLeft;
  final bool topRight;
  final bool bottomLeft;
  final bool bottomRight;

  const _CornerMark({
    required this.color,
    required this.size,
    required this.strokeWidth,
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _CornerPainter(
        color: color,
        strokeWidth: strokeWidth,
        topLeft: topLeft,
        topRight: topRight,
        bottomLeft: bottomLeft,
        bottomRight: bottomRight,
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final bool topLeft, topRight, bottomLeft, bottomRight;

  _CornerPainter({
    required this.color,
    required this.strokeWidth,
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (topLeft) {
      canvas.drawLine(Offset(0, size.height), const Offset(0, 0), paint);
      canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), paint);
    }
    if (topRight) {
      canvas.drawLine(Offset(size.width, size.height), Offset(size.width, 0), paint);
      canvas.drawLine(Offset(size.width, 0), const Offset(0, 0), paint);
    }
    if (bottomLeft) {
      canvas.drawLine(const Offset(0, 0), Offset(0, size.height), paint);
      canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), paint);
    }
    if (bottomRight) {
      canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), paint);
      canvas.drawLine(Offset(size.width, size.height), Offset(0, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
