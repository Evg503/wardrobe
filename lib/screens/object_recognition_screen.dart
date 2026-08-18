import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ObjectRecognitionScreen extends StatefulWidget {
  const ObjectRecognitionScreen({super.key});

  @override
  State<ObjectRecognitionScreen> createState() => _ObjectRecognitionScreenState();
}

class _ObjectRecognitionScreenState extends State<ObjectRecognitionScreen>
    with SingleTickerProviderStateMixin {
  bool _isRecognizing = false;
  final List<_RecognizedObject> _objects = [];
  late AnimationController _scanLineController;
  late Animation<double> _scanLineAnimation;

  final List<_RecognizedObject> _mockResults = const [
    _RecognizedObject('Диван', 'Мебель', 0.94, Icons.weekend, Color(0xFF2D4A3E)),
    _RecognizedObject('Журнальный стол', 'Мебель', 0.89, Icons.table_bar, Color(0xFF1A3A5C)),
    _RecognizedObject('Торшер', 'Освещение', 0.82, Icons.light, Color(0xFF5C3D1A)),
    _RecognizedObject('Ковёр', 'Текстиль', 0.77, Icons.texture, Color(0xFF3D1A5C)),
  ];

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
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    super.dispose();
  }

  void _startRecognition() {
    setState(() {
      _isRecognizing = true;
      _objects.clear();
    });

    // Имитация последовательного добавления объектов (заглушка)
    for (int i = 0; i < _mockResults.length; i++) {
      Future.delayed(Duration(milliseconds: 800 + i * 600), () {
        if (mounted) {
          setState(() {
            _objects.add(_mockResults[i]);
            if (i == _mockResults.length - 1) {
              _isRecognizing = false;
            }
          });
        }
      });
    }
  }

  void _clearResults() {
    setState(() {
      _objects.clear();
      _isRecognizing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Распознавание предметов'),
        actions: [
          if (_objects.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Очистить',
              onPressed: _clearResults,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Камера / видоискатель
            Expanded(
              flex: 5,
              child: _CameraPreview(
                isRecognizing: _isRecognizing,
                objects: _objects,
                scanLineAnimation: _scanLineAnimation,
              ),
            ),
            // Кнопка и список результатов
            Expanded(
              flex: 4,
              child: _ResultsPanel(
                objects: _objects,
                isRecognizing: _isRecognizing,
                onStart: _startRecognition,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraPreview extends StatelessWidget {
  final bool isRecognizing;
  final List<_RecognizedObject> objects;
  final Animation<double> scanLineAnimation;

  const _CameraPreview({
    required this.isRecognizing,
    required this.objects,
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Фоновая сетка (имитация камеры)
            CustomPaint(painter: _GridPainter()),

            // Имитация объектов в кадре
            if (objects.isNotEmpty) ...[
              Positioned(
                left: 40, top: 60, width: 120, height: 80,
                child: _BoundingBox(label: objects[0].name, confidence: objects[0].confidence),
              ),
              if (objects.length > 1)
                Positioned(
                  right: 50, top: 100, width: 90, height: 70,
                  child: _BoundingBox(label: objects[1].name, confidence: objects[1].confidence),
                ),
              if (objects.length > 2)
                Positioned(
                  left: 60, bottom: 40, width: 100, height: 60,
                  child: _BoundingBox(label: objects[2].name, confidence: objects[2].confidence),
                ),
            ],

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

            // Иконка "нет камеры" когда не сканируем и нет объектов
            if (!isRecognizing && objects.isEmpty)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      size: 48,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Нажмите "Распознать"',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

            // Счётчик объектов
            if (objects.isNotEmpty)
              Positioned(
                top: 12, right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
      ),
    );
  }

  String _plural(int n) {
    if (n == 1) return '';
    if (n >= 2 && n <= 4) return 'а';
    return 'ов';
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

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    const step = 36.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ResultsPanel extends StatelessWidget {
  final List<_RecognizedObject> objects;
  final bool isRecognizing;
  final VoidCallback onStart;

  const _ResultsPanel({
    required this.objects,
    required this.isRecognizing,
    required this.onStart,
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
            width: 40, height: 4,
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
                  objects.isEmpty ? 'Готово к распознаванию' : 'Найденные объекты',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                ),
                ElevatedButton.icon(
                  onPressed: isRecognizing ? null : onStart,
                  icon: isRecognizing
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search, size: 18),
                  label: Text(isRecognizing ? 'Анализ...' : 'Распознать'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: objects.isEmpty
                ? _EmptyResultsHint(isRecognizing: isRecognizing)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: objects.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _ObjectTile(object: objects[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyResultsHint extends StatelessWidget {
  final bool isRecognizing;

  const _EmptyResultsHint({required this.isRecognizing});

  @override
  Widget build(BuildContext context) {
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
}

class _ObjectTile extends StatelessWidget {
  final _RecognizedObject object;

  const _ObjectTile({required this.object});

  @override
  Widget build(BuildContext context) {
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
              color: object.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(object.icon, color: object.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  object.name,
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
                  color: object.color,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 60,
                child: LinearProgressIndicator(
                  value: object.confidence,
                  backgroundColor: Colors.grey.shade200,
                  color: object.color,
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
}

class _RecognizedObject {
  final String name;
  final String category;
  final double confidence;
  final IconData icon;
  final Color color;

  const _RecognizedObject(
    this.name,
    this.category,
    this.confidence,
    this.icon,
    this.color,
  );
}
