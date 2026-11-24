import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/ghst_theme_tokens.dart';
import 'ghst_button_icon.dart';

String maskPhoneNumber(String rawPhone) {
  final cleaned = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (cleaned.isEmpty) return '';
  if (cleaned.length < 7) return '***';
  return '${cleaned.substring(0, 4)}***${cleaned.substring(cleaned.length - 3)}';
}

class RecipientSignatureController extends ChangeNotifier {
  final List<List<Offset>> _strokes = <List<Offset>>[];

  List<List<Offset>> get strokes => List.unmodifiable(_strokes);

  bool get hasSignature =>
      _strokes.any((stroke) => stroke.length >= 2);

  int get pointCount =>
      _strokes.fold<int>(0, (sum, stroke) => sum + stroke.length);

  void startStroke(Offset localPosition) {
    _strokes.add(<Offset>[localPosition]);
    notifyListeners();
  }

  void appendPoint(Offset localPosition) {
    if (_strokes.isEmpty) {
      _strokes.add(<Offset>[localPosition]);
    } else {
      _strokes.last.add(localPosition);
    }
    notifyListeners();
  }

  void addSampleSignature() {
    _strokes
      ..clear()
      ..add(<Offset>[
        const Offset(42, 118),
        const Offset(78, 64),
        const Offset(112, 126),
        const Offset(154, 72),
        const Offset(198, 114),
        const Offset(256, 86),
        const Offset(312, 98),
      ])
      ..add(<Offset>[
        const Offset(58, 138),
        const Offset(180, 132),
        const Offset(295, 128),
      ]);
    notifyListeners();
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _strokes.clear();
    notifyListeners();
  }

  Future<Uint8List?> toPngBytes({
    Size canvasSize = const Size(380, 170),
    String? trackingCode,
    String? signerName,
  }) async {
    if (!hasSignature) return null;
    const outW = 640.0;
    const outH = 300.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, outW, outH));

    // Clean receipt background
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, outW, outH),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawRect(
      const Rect.fromLTWH(8, 8, outW - 16, outH - 16),
      Paint()
        ..color = const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Baseline guide
    canvas.drawLine(
      const Offset(36, outH - 64),
      const Offset(outW - 36, outH - 64),
      Paint()
        ..color = const Color(0xFFE2E8F0)
        ..strokeWidth = 1.5,
    );

    final scaleX = (outW - 48) / (canvasSize.width <= 0 ? 380.0 : canvasSize.width);
    final scaleY = (outH - 96) / (canvasSize.height <= 0 ? 170.0 : canvasSize.height);
    final inkPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    for (final stroke in _strokes) {
      if (stroke.length < 2) continue;
      final path = Path()
        ..moveTo(24 + stroke.first.dx * scaleX, 20 + stroke.first.dy * scaleY);
      for (var i = 1; i < stroke.length; i++) {
        final prev = stroke[i - 1];
        final curr = stroke[i];
        final midX = (prev.dx + curr.dx) / 2;
        final midY = (prev.dy + curr.dy) / 2;
        path.quadraticBezierTo(
          24 + prev.dx * scaleX,
          20 + prev.dy * scaleY,
          24 + midX * scaleX,
          20 + midY * scaleY,
        );
      }
      path.lineTo(24 + stroke.last.dx * scaleX, 20 + stroke.last.dy * scaleY);
      canvas.drawPath(path, inkPaint);
    }

    final footerParts = <String>[
      'XÁC NHẬN NHẬN HÀNG ĐIỆN TỬ',
      if (trackingCode != null && trackingCode.trim().isNotEmpty)
        trackingCode.trim(),
      if (signerName != null && signerName.trim().isNotEmpty)
        'Người ký: ${signerName.trim()}',
    ];
    final paragraphBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.left,
        maxLines: 1,
        fontSize: 13,
      ),
    )
      ..pushStyle(
        ui.TextStyle(
          color: const Color(0xFF475569),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      )
      ..addText(footerParts.join(' · '));
    final paragraph = paragraphBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: outW - 72));
    canvas.drawParagraph(paragraph, const Offset(36, outH - 46));

    final picture = recorder.endRecording();
    final image = await picture.toImage(outW.toInt(), outH.toInt());
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}

class RecipientSignaturePad extends StatefulWidget {
  const RecipientSignaturePad({
    super.key,
    required this.controller,
    this.requiredSignature = false,
    this.height = 165,
    this.enabled = true,
  });

  final RecipientSignatureController controller;
  final bool requiredSignature;
  final double height;
  final bool enabled;

  @override
  State<RecipientSignaturePad> createState() => _RecipientSignaturePadState();
}

class _RecipientSignaturePadState extends State<RecipientSignaturePad> {
  Size _canvasSize = const Size(380, 165);

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final signed = widget.controller.hasSignature;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                GhstButtonIcon(
                  signed ? Icons.verified_rounded : Icons.draw_outlined,
                  size: 17,
                  color: signed ? tokens.emerald.icon : tokens.sapphire.icon,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.requiredSignature
                        ? 'Chữ ký tay người nhận (Bắt buộc)'
                        : 'Chữ ký tay người nhận (Khuyến nghị)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: tokens.ink,
                    ),
                  ),
                ),
                if (signed)
                  TextButton.icon(
                    key: const ValueKey('signature-pad-clear'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: widget.enabled ? widget.controller.clear : null,
                    icon: const GhstButtonIcon(Icons.cleaning_services_outlined, size: 15),
                    label: const Text('Ký lại'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth.isFinite && constraints.maxWidth > 80
                    ? constraints.maxWidth
                    : 380.0;
                _canvasSize = Size(width, widget.height);
                return Container(
                  key: const ValueKey('recipient-signature-canvas'),
                  height: widget.height,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: signed ? tokens.emerald.border : tokens.border,
                      width: signed ? 1.6 : 1.1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (!signed)
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const GhstButtonIcon(
                                  Icons.gesture_rounded,
                                  size: 24,
                                  color: Color(0xFF94A3B8),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Người nhận ký trực tiếp bằng ngón tay tại đây',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: widget.enabled
                              ? (details) => widget.controller.startStroke(
                                  _clampOffset(details.localPosition, _canvasSize),
                                )
                              : null,
                          onPanUpdate: widget.enabled
                              ? (details) => widget.controller.appendPoint(
                                  _clampOffset(details.localPosition, _canvasSize),
                                )
                              : null,
                          child: CustomPaint(
                            painter: _SignatureCanvasPainter(
                              strokes: widget.controller.strokes,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  static Offset _clampOffset(Offset raw, Size size) => Offset(
    raw.dx.clamp(4.0, size.width - 4.0),
    raw.dy.clamp(4.0, size.height - 4.0),
  );
}

class _SignatureCanvasPainter extends CustomPainter {
  const _SignatureCanvasPainter({required this.strokes});

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(20, size.height - 28),
      Offset(size.width - 20, size.height - 28),
      guidePaint,
    );

    final strokePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        final prev = stroke[i - 1];
        final curr = stroke[i];
        path.quadraticBezierTo(
          prev.dx,
          prev.dy,
          (prev.dx + curr.dx) / 2,
          (prev.dy + curr.dy) / 2,
        );
      }
      path.lineTo(stroke.last.dx, stroke.last.dy);
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignatureCanvasPainter oldDelegate) => true;
}

Future<void> showMaskedContactSheet({
  required BuildContext context,
  required String roleLabel,
  required String contactName,
  required String rawPhone,
  required String? maskedPhone,
  required Future<void> Function(String phone) onCall,
  Future<void> Function(String quickMessage)? onSendQuickMessage,
  List<String> quickPresets = const [],
}) async {
  final displayMasked = (maskedPhone != null && maskedPhone.trim().isNotEmpty)
      ? maskedPhone.trim()
      : maskPhoneNumber(rawPhone);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) {
      final tokens = GhstThemeTokens.of(sheetCtx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: tokens.emerald.fill,
                    foregroundColor: tokens.emerald.foreground,
                    child: const GhstButtonIcon(Icons.shield_outlined),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Liên hệ an toàn · $roleLabel',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: tokens.ink,
                          ),
                        ),
                        Text(
                          '$contactName · $displayMasked',
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.inkSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.sapphire.fill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.sapphire.border),
                ),
                child: Row(
                  children: [
                    GhstButtonIcon(
                      Icons.privacy_tip_outlined,
                      size: 18,
                      color: tokens.sapphire.icon,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Số điện thoại cá nhân được ẩn một phần ($displayMasked) để bảo vệ quyền riêng tư sau khi hoàn tất chuyến giao.',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.sapphire.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (quickPresets.isNotEmpty && onSendQuickMessage != null) ...[
                const SizedBox(height: 14),
                Text(
                  'Gửi nhanh tin nhắn trong ứng dụng (Không lộ SĐT)',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in quickPresets)
                      ActionChip(
                        avatar: const GhstButtonIcon.glyph(
                          GhstActionKind.chat,
                          size: 14,
                        ),
                        label: Text(
                          preset,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          onSendQuickMessage(preset);
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (rawPhone.trim().isNotEmpty)
                    FilledButton.icon(
                      key: const ValueKey('masked-contact-call-btn'),
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        onCall(rawPhone);
                      },
                      icon: const GhstButtonIcon(Icons.phone_in_talk_rounded, size: 17),
                      label: Text('Kết nối cuộc gọi ($displayMasked)'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: displayMasked));
                      Navigator.pop(sheetCtx);
                    },
                    icon: const GhstButtonIcon(Icons.copy_outlined, size: 16),
                    label: const Text('Sao chép mã số ẩn'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
