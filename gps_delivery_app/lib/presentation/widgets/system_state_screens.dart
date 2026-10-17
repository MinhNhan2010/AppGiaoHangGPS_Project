import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import 'animated_3d_ui_icons.dart';

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
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Animated3dIconBadge(
                        style: Icon3dStyle.scooterExpress,
                        size: 124,
                        showRadarPulse: true,
                        isSelected: true,
                      ),
                      SizedBox(height: AppSpacing.md),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.all(Radius.circular(20)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          child: Text(
                            'FLASH DELIVERY 3D GPS',
                            style: TextStyle(
                              color: AppColors.surface,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
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
            const Animated3dIconBadge(
              style: Icon3dStyle.parcelBox,
              size: 108,
              showRadarPulse: true,
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

/// Hình 8.51 & Mục 8.6: Bản đồ 3D Perspective Navigation Widget chiếu tọa độ thực tế
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
  final List<GeoPoint> routePoints;

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
    this.routePoints = const [],
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRoute = routePoints.length >= 2
        ? routePoints
        : AppStateStore.instance.activeRoutePolyline;
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
                        routePoints: effectiveRoute,
                      ),
                    ),
                  ),
                  // Thanh tiêu đề điều hướng từng chặng Turn-by-Turn (Hình 8.18 & Hình 8.51)
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
                                      ? 'Góc nhìn 3D Pitch 55° • ${effectiveRoute.length} điểm GPS • $roadName'
                                      : 'Chế độ 2D Overview • ${effectiveRoute.length} điểm GPS • $roadName',
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
                  // Huy hiệu đồng hồ tốc độ (35 km/h - Hình 8.51)
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
                  // Cụm nút chuyển đổi 2D/3D & La bàn định hướng (Hình 8.51)
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
  final List<GeoPoint> routePoints;

  const _Map3dCanvasPainter({
    required this.is3dMode,
    required this.progressFraction,
    required this.drawnPolygonPoints,
    required this.routePoints,
  });

  /// Chiếu danh sách tọa độ địa lý (vĩ độ, kinh độ) thực tế lên không gian khung vẽ 2D/3D
  List<Offset> _projectGeoPointsToCanvas(Size size) {
    if (routePoints.length < 2) {
      return [
        Offset(size.width * 0.35, size.height * 0.90),
        Offset(size.width * 0.52, size.height * 0.52),
        Offset(size.width * 0.68, size.height * 0.24),
      ];
    }
    double minLat = routePoints.first.latitude;
    double maxLat = routePoints.first.latitude;
    double minLng = routePoints.first.longitude;
    double maxLng = routePoints.first.longitude;

    for (final pt in routePoints) {
      minLat = math.min(minLat, pt.latitude);
      maxLat = math.max(maxLat, pt.latitude);
      minLng = math.min(minLng, pt.longitude);
      maxLng = math.max(maxLng, pt.longitude);
    }

    final latSpan = (maxLat - minLat).abs() < 1e-6 ? 0.01 : (maxLat - minLat);
    final lngSpan = (maxLng - minLng).abs() < 1e-6 ? 0.01 : (maxLng - minLng);

    final projected = <Offset>[];
    for (final pt in routePoints) {
      final normX = ((pt.longitude - minLng) / lngSpan).clamp(0.0, 1.0);
      final normY = (1.0 - ((pt.latitude - minLat) / latSpan)).clamp(0.0, 1.0);

      // Biến đổi phối cảnh hình thang khi bật góc nhìn 3D Pitch 55 độ
      final double canvasY = size.height * (0.22 + normY * 0.68);
      final double depthFactor =
          is3dMode ? (0.55 + 0.45 * normY) : 1.0;
      final double centeredX = (normX - 0.5) * depthFactor + 0.5;
      final double canvasX = size.width * (0.24 + centeredX * 0.52);

      projected.add(Offset(canvasX, canvasY));
    }
    return projected;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFDCE3EA);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Vẽ mặt đường phối cảnh 3D
    final roadPaint = Paint()..color = const Color(0xFF4A5568);
    final roadPath = Path()
      ..moveTo(size.width * 0.20, size.height)
      ..lineTo(size.width * (is3dMode ? 0.42 : 0.34), size.height * 0.18)
      ..lineTo(size.width * (is3dMode ? 0.66 : 0.72), size.height * 0.18)
      ..lineTo(size.width * 0.78, size.height)
      ..close();
    canvas.drawPath(roadPath, roadPaint);

    // Vẽ khối nhà 3D Extruded Buildings (#D0D7DE với độ mờ 0.65 - Bảng 16)
    if (is3dMode) {
      final bldgPaint = Paint()
        ..color = AppColors.buildingExtrusion.withValues(alpha: 0.85);
      final roofPaint = Paint()..color = const Color(0xFFE2E8F0);
      final blocks = [
        Rect.fromLTWH(size.width * 0.05, size.height * 0.42, 75, 95),
        Rect.fromLTWH(size.width * 0.14, size.height * 0.25, 65, 80),
        Rect.fromLTWH(size.width * 0.72, size.height * 0.35, 85, 110),
        Rect.fromLTWH(size.width * 0.68, size.height * 0.18, 60, 70),
      ];
      for (final rect in blocks) {
        canvas.drawRect(rect, bldgPaint);
        canvas.drawRect(rect.deflate(6), roofPaint);
      }
    }

    // Vẽ đa giác vùng Geofence tùy chỉnh nếu có (UC44 - Hình 8.33)
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

    // Chiếu lộ trình tọa độ GPS thực tế lên dải 3D Route Ribbon (#00B4D8 với viền #0077B6 - Bảng 16)
    final casingPaint = Paint()
      ..color = AppColors.routeRibbonCasing
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final ribbonPaint = Paint()
      ..color = AppColors.routeRibbonFill
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final screenPts = _projectGeoPointsToCanvas(size);
    final routePath = Path()..moveTo(screenPts.first.dx, screenPts.first.dy);
    for (var i = 1; i < screenPts.length; i++) {
      routePath.lineTo(screenPts[i].dx, screenPts[i].dy);
    }

    canvas.drawPath(routePath, casingPaint);
    canvas.drawPath(routePath, ribbonPaint);

    // Vẽ ghim điểm lấy hàng (đầu lộ trình) và điểm giao hàng (cuối lộ trình)
    canvas.drawCircle(screenPts.first, 6, Paint()..color = AppColors.primary);
    canvas.drawCircle(screenPts.last, 8, Paint()..color = AppColors.accent);

    // Nội suy vị trí biểu tượng xe Tài xế 3D dọc theo từng phân đoạn lộ trình chiếu thực tế
    final t = progressFraction.clamp(0.0, 1.0);
    final totalSegments = screenPts.length - 1;
    final exactIdx = t * totalSegments;
    final segIdx = exactIdx.floor().clamp(0, totalSegments - 1);
    final segT = (exactIdx - segIdx).clamp(0.0, 1.0);
    final driverCenter =
        Offset.lerp(screenPts[segIdx], screenPts[segIdx + 1], segT)!;

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
      oldDelegate.drawnPolygonPoints.length != drawnPolygonPoints.length ||
      oldDelegate.routePoints.length != routePoints.length;
}

