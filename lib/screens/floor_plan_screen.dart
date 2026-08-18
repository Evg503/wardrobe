import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/camera_preview_widget.dart';

class FloorPlanScreen extends StatefulWidget {
  const FloorPlanScreen({super.key});

  @override
  State<FloorPlanScreen> createState() => _FloorPlanScreenState();
}

class _FloorPlanScreenState extends State<FloorPlanScreen>
    with SingleTickerProviderStateMixin {
  bool _isScanning = false;
  bool _hasPlan = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
      _hasPlan = false;
    });
    // Имитация сканирования (заглушка)
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _hasPlan = true;
        });
      }
    });
  }

  void _resetScan() {
    setState(() {
      _hasPlan = false;
      _isScanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('План квартиры'),
        actions: [
          if (_hasPlan)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Поделиться',
              onPressed: () => _showSnackBar(context, 'Экспорт плана (в разработке)'),
            ),
        ],
      ),
      body: SafeArea(
        child: _isScanning
            ? _ScanningView(pulseAnimation: _pulseAnimation)
            : _hasPlan
                ? _PlanView(onRescan: _resetScan)
                : _EmptyView(onStart: _startScan),
      ),
    );
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onStart;

  const _EmptyView({required this.onStart});

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
            child: const Icon(
              Icons.map_outlined,
              size: 56,
              color: AppTheme.primary,
            ),
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
            'Направьте камеру на комнату и медленно обведите\nпространство вокруг. Приложение создаст\nточный 2D-план с размерами.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.6,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.amber, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Лучший результат: iPhone с LiDAR (12 Pro+)\nили Android с ToF-сенсором',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.amber.shade800,
                        ),
                  ),
                ),
              ],
            ),
          ),
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

class _ScanningView extends StatelessWidget {
  final Animation<double> pulseAnimation;

  const _ScanningView({required this.pulseAnimation});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(24),
              ),
              child: CameraPreviewWidget(
                overlays: [
                  // Пульсирующий индикатор сканирования
                  Center(
                    child: ScaleTransition(
                      scale: pulseAnimation,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.secondary.withValues(alpha: 0.7),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.secondary.withValues(alpha: 0.2),
                              border: Border.all(
                                color: AppTheme.secondary,
                                width: 3,
                              ),
                            ),
                            child: const Icon(
                              Icons.radar,
                              color: AppTheme.secondary,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Угловые маркеры
                  ..._buildCornerMarkers(),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            children: [
              const LinearProgressIndicator(
                backgroundColor: Colors.white24,
                color: AppTheme.secondary,
              ),
              const SizedBox(height: 16),
              Text(
                'Сканирование...',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Медленно обводите камерой комнату по периметру',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCornerMarkers() {
    const color = AppTheme.secondary;
    const size = 24.0;
    const width = 3.0;
    return [
      Positioned(
        top: 20, left: 20,
        child: _CornerMark(color: color, size: size, strokeWidth: width, topLeft: true),
      ),
      Positioned(
        top: 20, right: 20,
        child: _CornerMark(color: color, size: size, strokeWidth: width, topRight: true),
      ),
      Positioned(
        bottom: 20, left: 20,
        child: _CornerMark(color: color, size: size, strokeWidth: width, bottomLeft: true),
      ),
      Positioned(
        bottom: 20, right: 20,
        child: _CornerMark(color: color, size: size, strokeWidth: width, bottomRight: true),
      ),
    ];
  }
}

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
      canvas.drawLine(Offset(0, size.height), Offset(0, 0), paint);
      canvas.drawLine(Offset(0, 0), Offset(size.width, 0), paint);
    }
    if (topRight) {
      canvas.drawLine(Offset(size.width, size.height), Offset(size.width, 0), paint);
      canvas.drawLine(Offset(size.width, 0), Offset(0, 0), paint);
    }
    if (bottomLeft) {
      canvas.drawLine(Offset(0, 0), Offset(0, size.height), paint);
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


class _PlanView extends StatelessWidget {
  final VoidCallback onRescan;

  const _PlanView({required this.onRescan});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Превью плана
          Container(
            height: 300,
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
                painter: _FloorPlanPainter(),
                size: Size.infinite,
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
          _RoomInfo(
            rooms: const [
              _RoomData('Гостиная', '5.2 м × 4.1 м', '21.3 м²', Icons.weekend),
              _RoomData('Спальня', '3.8 м × 3.2 м', '12.2 м²', Icons.bed),
              _RoomData('Кухня', '3.5 м × 2.8 м', '9.8 м²', Icons.kitchen),
              _RoomData('Ванная', '2.1 м × 1.8 м', '3.8 м²', Icons.bathtub),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _TotalStat('Общая площадь', '47.1 м²'),
                _VertDivider(),
                _TotalStat('Комнат', '4'),
                _VertDivider(),
                _TotalStat('Точность', '±2 см'),
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.download),
                  label: const Text('Сохранить'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 40, color: AppTheme.primary.withValues(alpha: 0.2));
  }
}

class _TotalStat extends StatelessWidget {
  final String label;
  final String value;

  const _TotalStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _RoomData {
  final String name;
  final String dimensions;
  final String area;
  final IconData icon;

  const _RoomData(this.name, this.dimensions, this.area, this.icon);
}

class _RoomInfo extends StatelessWidget {
  final List<_RoomData> rooms;

  const _RoomInfo({required this.rooms});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: rooms.map((room) {
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
                child: Icon(room.icon, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      room.dimensions,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                room.area,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _FloorPlanPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wallPaint = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    final roomFill = Paint()
      ..color = AppTheme.secondary.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final doorPaint = Paint()
      ..color = Colors.brown.shade300
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final w = size.width;
    final h = size.height;
    const p = 30.0; // padding

    // Общий контур квартиры
    final outline = Rect.fromLTRB(p, p, w - p, h - p);
    canvas.drawRect(outline, roomFill);
    canvas.drawRect(outline, wallPaint);

    // Внутренние стены
    // Вертикальная стена делящая гостиную и коридор/спальню
    final midX = p + (w - 2 * p) * 0.55;
    canvas.drawLine(Offset(midX, p), Offset(midX, h - p), wallPaint);

    // Горизонтальная стена (кухня/ванная внизу справа)
    final midY = p + (h - 2 * p) * 0.55;
    canvas.drawLine(Offset(midX, midY), Offset(w - p, midY), wallPaint);

    // Горизонтальная стена (спальня от коридора)
    final topMidY = p + (h - 2 * p) * 0.45;
    canvas.drawLine(Offset(midX, p), Offset(midX, topMidY), wallPaint);

    // Подписи комнат
    void drawLabel(String text, Offset center) {
      textPainter
        ..text = TextSpan(
          text: text,
          style: TextStyle(
            color: AppTheme.primary.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        )
        ..layout();
      textPainter.paint(
        canvas,
        center - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }

    drawLabel('Гостиная', Offset((p + midX) / 2, (p + h - p) / 2));
    drawLabel('Спальня', Offset((midX + w - p) / 2, (p + midY) / 2));
    drawLabel('Кухня', Offset((midX + w - p) / 2, (midY + h - p) / 2 - 10));
    drawLabel('Ванная', Offset((midX + w - p) / 2, (midY + h - p) / 2 + 14));

    // Дверные проёмы (простые дуги)
    canvas.drawArc(
      Rect.fromCenter(center: Offset(p + 40, p + 40), width: 40, height: 40),
      0, 1.5708, false, doorPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
