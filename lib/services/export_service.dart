import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show GlobalKey;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'ar_scan_service.dart';

/// Результат экспорта — путь к файлу и его тип.
class ExportResult {
  final String path;
  final ExportFormat format;

  ExportResult({required this.path, required this.format});
}

enum ExportFormat { png, pdf }

/// Сервис экспорта плана квартиры в PNG и PDF.
///
/// PNG рендерится через [RepaintBoundary] → [RenderRepaintBoundary].
/// PDF строится через пакет `pdf` с векторной отрисовкой плоскостей.
class ExportService {
  /// Рендерит виджет, обёрнутый в [RepaintBoundary] с данным [key], в PNG-файл.
  /// Возвращает путь к сохранённому файлу.
  static Future<ExportResult> exportPng(GlobalKey repaintKey) async {
    final boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('RepaintBoundary not found');

    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw StateError('Failed to encode PNG');

    final bytes = byteData.buffer.asUint8List();
    final file = await _writeToTemp('floor_plan_${_timestamp()}.png', bytes);
    return ExportResult(path: file.path, format: ExportFormat.png);
  }

  /// Строит PDF с векторным планом и текстовой статистикой из [result].
  /// Возвращает путь к сохранённому файлу.
  static Future<ExportResult> exportPdf(ScanResult result) async {
    final doc = pw.Document();

    final horizontal =
        result.planes.where((p) => p.type == PlaneType.horizontal).toList();
    final vertical =
        result.planes.where((p) => p.type == PlaneType.vertical).toList();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Заголовок
              pw.Text(
                'План квартиры',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Дата: ${_formatDate(result.timestamp)}',
                style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600),
              ),
              pw.SizedBox(height: 20),

              // Векторный план
              pw.Container(
                height: 300,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.CustomPaint(
                  painter: (canvas, size) =>
                      _drawPlan(canvas, size, horizontal, vertical),
                ),
              ),
              pw.SizedBox(height: 20),

              // Итоги
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _statCell('Площадь пола',
                      '${result.totalFloorArea.toStringAsFixed(1)} м²'),
                  _statCell('Поверхностей', '${result.planes.length}'),
                  _statCell('Стен', '${vertical.length}'),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 12),

              // Таблица поверхностей
              if (horizontal.isNotEmpty) ...[
                pw.Text('Горизонтальные поверхности (полы)',
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                ...horizontal.asMap().entries.map((e) => _planeRow(
                    'Поверхность ${e.key + 1}', e.value)),
                pw.SizedBox(height: 12),
              ],
              if (vertical.isNotEmpty) ...[
                pw.Text('Вертикальные поверхности (стены)',
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                ...vertical.asMap().entries.map(
                    (e) => _planeRow('Стена ${e.key + 1}', e.value)),
              ],

              pw.Spacer(),
              pw.Divider(color: PdfColors.grey200),
              pw.Text(
                'Сформировано приложением Wardrobe',
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey400),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await doc.save();
    final file = await _writeToTemp('floor_plan_${_timestamp()}.pdf', bytes);
    return ExportResult(path: file.path, format: ExportFormat.pdf);
  }

  /// Шарит файл через системный шит (Files, WhatsApp, Telegram и т.д.)
  static Future<void> share(ExportResult result, {String? subject}) async {
    final file = XFile(result.path);
    await Share.shareXFiles(
      [file],
      subject: subject ?? 'План квартиры',
    );
  }

  // ── Вспомогательные ───────────────────────────────────────────────────────

  static void _drawPlan(
    PdfGraphics canvas,
    PdfPoint size,
    List<DetectedPlane> horizontal,
    List<DetectedPlane> vertical,
  ) {
    const padding = 20.0;
    final w = size.x;
    final h = size.y;

    if (horizontal.isEmpty && vertical.isEmpty) {
      // Заглушка
      canvas
        ..setColor(PdfColors.grey200)
        ..drawRect(padding, padding, w - 2 * padding, h - 2 * padding)
        ..fillPath();
      return;
    }

    // Масштаб по максимальному экстенту горизонтальных плоскостей
    double maxExtent = 0;
    for (final p in horizontal) {
      if (p.extent.x > maxExtent) maxExtent = p.extent.x;
      if (p.extent.y > maxExtent) maxExtent = p.extent.y;
    }
    if (maxExtent == 0) maxExtent = 5.0;
    final scale = (w - 2 * padding) / maxExtent;

    // Рисуем горизонтальные плоскости (полы) — синий контур
    double offsetY = padding;
    for (final plane in horizontal) {
      final pw2 = plane.extent.x * scale;
      final ph2 = (plane.extent.y * scale).clamp(30.0, h - 2 * padding);
      canvas
        ..setColor(PdfColors.blue50)
        ..drawRect(padding, h - offsetY - ph2, pw2, ph2)
        ..fillPath();
      canvas
        ..setColor(PdfColors.blueAccent)
        ..setLineWidth(1.5)
        ..drawRect(padding, h - offsetY - ph2, pw2, ph2)
        ..strokePath();
      offsetY += ph2 + 8;
      if (offsetY > h - padding) break;
    }

    // Рисуем вертикальные плоскости (стены) — серые линии по краям
    canvas.setColor(PdfColors.grey600);
    canvas.setLineWidth(3);
    for (final plane in vertical) {
      final pw2 = (plane.extent.x * scale).clamp(10.0, w - 2 * padding);
      final x = padding + (w - 2 * padding - pw2) / 2;
      canvas
        ..moveTo(x, padding)
        ..lineTo(x + pw2, padding)
        ..strokePath();
    }
  }

  static pw.Widget _statCell(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 15, fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo800)),
        pw.SizedBox(height: 2),
        pw.Text(label,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
      ],
    );
  }

  static pw.Widget _planeRow(String name, DetectedPlane plane) {
    final area = (plane.extent.x * plane.extent.y).toStringAsFixed(1);
    final size =
        '${plane.extent.x.toStringAsFixed(2)} × ${plane.extent.y.toStringAsFixed(2)} м';
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(name, style: const pw.TextStyle(fontSize: 11))),
          pw.Text(size,
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          pw.SizedBox(width: 16),
          pw.Text('$area м²',
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold,
                  color: PdfColors.indigo700)),
        ],
      ),
    );
  }

  static Future<File> _writeToTemp(String name, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  static String _timestamp() {
    final now = DateTime.now();
    return '${now.year}${_pad(now.month)}${_pad(now.day)}_'
        '${_pad(now.hour)}${_pad(now.minute)}';
  }

  static String _formatDate(DateTime dt) {
    return '${_pad(dt.day)}.${_pad(dt.month)}.${dt.year} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
