import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/local/app_state_store.dart';

/// Hình 8.47: Onboarding Screen ("Giao hàng siêu tốc 30 phút")
class OnboardingStateScreen extends StatelessWidget {
  final VoidCallback onGetStarted;

  const OnboardingStateScreen({super.key, required this.onGetStarted});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEBF4FF), Color(0xFFFFF5EB)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppSpacing.lg),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delivery_dining,
                          size: 72,
                          color: AppColors.surface,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'FLASH DELIVERY 3D GPS',
                          style: TextStyle(
                            color: AppColors.surface,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Giao hàng siêu tốc 30 phút',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Cam kết giao đến tay bạn chỉ trong vòng 30 phút. Định vị GPS 3D thời gian thực, nhanh chóng, tiện lợi mọi nơi.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 24,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const CircleAvatar(
                    radius: 4,
                    backgroundColor: AppColors.divider,
                  ),
                  const SizedBox(width: 6),
                  const CircleAvatar(
                    radius: 4,
                    backgroundColor: AppColors.divider,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                  ),
                  onPressed: onGetStarted,
                  child: const Text('Bắt đầu ngay'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hình 8.48: Empty State ("Bạn chưa có đơn hàng nào!")
class EmptyOrdersStateWidget extends StatelessWidget {
  final VoidCallback onCreateOrder;

  const EmptyOrdersStateWidget({super.key, required this.onCreateOrder});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 56,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Bạn chưa có đơn hàng nào!',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Khám phá các dịch vụ giao hàng thông minh ngay hôm nay',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              ),
              onPressed: onCreateOrder,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Tạo đơn hàng ngay'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hình 8.49: Offline Banner & Local GPS Queue Dialog
class OfflineQueueBanner extends StatelessWidget {
  final AppStateStore store;

  const OfflineQueueBanner({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    if (!store.isOfflineMode) return const SizedBox.shrink();
    return Material(
      color: AppColors.danger,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, color: AppColors.surface, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Mất kết nối mạng Internet. Tọa độ đang được lưu tạm (${store.offlineQueueCount} gói tin trong SQLite)',
                style: const TextStyle(
                  color: AppColors.surface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.surface,
                backgroundColor: Colors.white24,
              ),
              onPressed: () => store.toggleOfflineSimulation(false),
              child: const Text('Thử kết nối lại'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hình 8.50: Shimmer Skeleton Loading List
class SkeletonOrderListWidget extends StatelessWidget {
  const SkeletonOrderListWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.shimmerBase,
                    borderRadius: BorderRadius.circular(AppSpacing.sm),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 140,
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppColors.shimmerBase,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.shimmerHighlight,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 100,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.shimmerBase,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Hình 8.51 & Mục 8.6: Bản đồ 3D Perspective Navigation Widget
class Map3dPerspectiveWidget extends StatelessWidget {
  final String nextTurnInstruction;
  final String roadName;
  final double speedKmh;
  final bool is3dMode;
  final VoidCallback? onToggle3d;
  final double height;
  final double progressFraction;
  final ValueChanged<Offset>? onTapRelativePoint;
  final List<Offset> drawnPolygonPoints;

  const Map3dPerspectiveWidget({
    super.key,
    this.nextTurnInstruction = 'Rẽ phải sau 150m - Phố Huế',
    this.roadName = 'Đường Bà Triệu',
    this.speedKmh = 35.0,
    this.is3dMode = true,
    this.onToggle3d,
    this.height = 280,
    this.progressFraction = 0.35,
    this.onTapRelativePoint,
    this.drawnPolygonPoints = const [],
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              onTapUp: onTapRelativePoint == null
                  ? null
                  : (details) {
                      final relX = (details.localPosition.dx /
                              constraints.maxWidth)
                          .clamp(0.0, 1.0);
                      final relY = (details.localPosition.dy /
                              constraints.maxHeight)
                          .clamp(0.0, 1.0);
                      onTapRelativePoint!(Offset(relX, relY));
                    },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _Map3dCanvasPainter(
                        is3dMode: is3dMode,
                        progressFraction: progressFraction,
                        drawnPolygonPoints: drawnPolygonPoints,
                      ),
                    ),
                  ),
                  // Turn-by-Turn Navigation Header (Hình 8.18 & Hình 8.51)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.darkSidebar.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.turn_right,
                            color: AppColors.surface,
                            size: 28,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nextTurnInstruction,
                                  style: const TextStyle(
                                    color: AppColors.surface,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  is3dMode
                                      ? 'Góc nhìn 3D Pitch 55° • Zoom 17.0 • $roadName'
                                      : 'Chế độ 2D Overview • Zoom 14.5 • $roadName',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Speedometer Badge (35 km/h - Hình 8.51)
                  Positioned(
                    top: 78,
                    right: 14,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.darkSidebar,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.danger, width: 2.5),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            speedKmh.toStringAsFixed(0),
                            style: const TextStyle(
                              color: AppColors.surface,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const Text(
                            'km/h',
                            style: TextStyle(color: Colors.white70, fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 3D Toggle & Compass Buttons (Hình 8.51)
                  Positioned(
                    bottom: 16,
                    right: 14,
                    child: Column(
                      children: [
                        InkWell(
                          onTap: onToggle3d,
                          child: Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.surface,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.black26, blurRadius: 6),
                              ],
                            ),
                            child: Text(
                              is3dMode ? '3D' : '2D',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: 6),
                            ],
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.navigation,
                                size: 16,
                                color: AppColors.danger,
                              ),
                              Text(
                                'N',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Map3dCanvasPainter extends CustomPainter {
  final bool is3dMode;
  final double progressFraction;
  final List<Offset> drawnPolygonPoints;

  const _Map3dCanvasPainter({
    required this.is3dMode,
    required this.progressFraction,
    required this.drawnPolygonPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFDCE3EA);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Draw perspective road polygon
    final roadPaint = Paint()..color = const Color(0xFF4A5568);
    final roadPath = Path()
      ..moveTo(size.width * 0.22, size.height)
      ..lineTo(size.width * (is3dMode ? 0.45 : 0.38), size.height * 0.18)
      ..lineTo(size.width * (is3dMode ? 0.62 : 0.65), size.height * 0.18)
      ..lineTo(size.width * 0.58, size.height)
      ..close();
    canvas.drawPath(roadPath, roadPaint);

    // Draw 3D Extruded Buildings (#D0D7DE with 0.65 opacity - Table 16)
    if (is3dMode) {
      final bldgPaint = Paint()
        ..color = AppColors.buildingExtrusion.withValues(alpha: 0.85);
      final roofPaint = Paint()..color = const Color(0xFFE2E8F0);
      final blocks = [
        Rect.fromLTWH(size.width * 0.05, size.height * 0.42, 75, 95),
        Rect.fromLTWH(size.width * 0.14, size.height * 0.25, 65, 80),
        Rect.fromLTWH(size.width * 0.68, size.height * 0.35, 85, 110),
        Rect.fromLTWH(size.width * 0.64, size.height * 0.18, 60, 70),
      ];
      for (final rect in blocks) {
        canvas.drawRect(rect, bldgPaint);
        canvas.drawRect(rect.deflate(6), roofPaint);
      }
    }

    // Draw custom Geofence Polygon if present (UC44 - Hình 8.33)
    if (drawnPolygonPoints.isNotEmpty) {
      final polyFill = Paint()
        ..color = AppColors.accent.withValues(alpha: 0.28)
        ..style = PaintingStyle.fill;
      final polyStroke = Paint()
        ..color = AppColors.accent
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;

      final polyPath = Path();
      for (var i = 0; i < drawnPolygonPoints.length; i++) {
        final pt = Offset(
          drawnPolygonPoints[i].dx * size.width,
          drawnPolygonPoints[i].dy * size.height,
        );
        if (i == 0) {
          polyPath.moveTo(pt.dx, pt.dy);
        } else {
          polyPath.lineTo(pt.dx, pt.dy);
        }
        canvas.drawCircle(pt, 5, Paint()..color = AppColors.danger);
      }
      if (drawnPolygonPoints.length >= 3) {
        polyPath.close();
        canvas.drawPath(polyPath, polyFill);
      }
      canvas.drawPath(polyPath, polyStroke);
    }

    // Draw 3D Route Ribbon (#00B4D8 with #0077B6 casing - Table 16)
    final casingPaint = Paint()
      ..color = AppColors.routeRibbonCasing
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final ribbonPaint = Paint()
      ..color = AppColors.routeRibbonFill
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final p0 = Offset(size.width * 0.40, size.height * 0.92);
    final p1 = Offset(size.width * 0.53, size.height * 0.26);
    final p2 = Offset(size.width * 0.72, size.height * 0.26);

    final routePath = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy);

    canvas.drawPath(routePath, casingPaint);
    canvas.drawPath(routePath, ribbonPaint);

    // Draw Drop-off Pin at end of route
    canvas.drawCircle(p2, 8, Paint()..color = AppColors.accent);

    // Interpolate Driver 3D Marker position along p0 -> p1 -> p2
    final t = progressFraction.clamp(0.0, 1.0);
    final Offset driverCenter;
    if (t <= 0.7) {
      final segT = t / 0.7;
      driverCenter = Offset.lerp(p0, p1, segT)!;
    } else {
      final segT = (t - 0.7) / 0.3;
      driverCenter = Offset.lerp(p1, p2, segT)!;
    }

    canvas.drawCircle(
      driverCenter,
      16,
      Paint()..color = AppColors.success.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      driverCenter,
      10,
      Paint()..color = AppColors.success,
    );
  }

  @override
  bool shouldRepaint(covariant _Map3dCanvasPainter oldDelegate) =>
      oldDelegate.is3dMode != is3dMode ||
      oldDelegate.progressFraction != progressFraction ||
      oldDelegate.drawnPolygonPoints.length != drawnPolygonPoints.length;
}
