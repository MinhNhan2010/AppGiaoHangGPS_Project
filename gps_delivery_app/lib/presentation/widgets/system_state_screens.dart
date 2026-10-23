import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/config/env_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/entities/geo_point.dart';
import 'animated_3d_ui_icons.dart';

/// Chế độ hiển thị Bản đồ theo đúng ngữ cảnh từng vai trò sau khi đăng nhập
enum MapViewMode {
  /// Khách hàng xem trước lộ trình khi tạo đơn (ẩn đồng hồ tốc độ km/h & mũi tên buồng lái tài xế)
  customerPreview,

  /// Khách hàng theo dõi trực tiếp tài xế đang giao đơn
  customerLiveTracking,

  /// Tài xế bật Online Radar chờ nhận đơn xung quanh bán kính 3km - 8km
  driverRadar,

  /// Tài xế điều hướng Turn-by-Turn 3D Pitch 55°
  driverTurnByTurn,

  /// Cửa hàng B2B & Quản trị viên giám sát đa tài xế / đa vận đơn trên toàn thành phố
  fleetOverview,
}

/// Onboarding Screen ("Giao hàng siêu tốc 30 phút") theo phong cách Studio nghienai.click
class OnboardingStateScreen extends StatelessWidget {
  final VoidCallback onGetStarted;

  const OnboardingStateScreen({super.key, required this.onGetStarted});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.techBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  border: Border.all(color: AppColors.ink, width: 2.0),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.violet,
                      offset: Offset(10, 10),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.techBg,
                          border: Border.all(color: AppColors.ink, width: 1.5),
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
                                color: AppColors.acid,
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                child: Text(
                                  'FLASH DELIVERY 3D GPS',
                                  style: TextStyle(
                                    color: AppColors.techBg,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'Consolas',
                                    fontSize: 12,
                                    letterSpacing: 1.0,
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
                          width: 26,
                          height: 8,
                          color: AppColors.violet,
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          color: AppColors.ink,
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          color: AppColors.ink,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.ink,
                            offset: Offset(5, 5),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.violet,
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                            side: BorderSide(color: AppColors.ink, width: 1.5),
                          ),
                        ),
                        onPressed: onGetStarted,
                        child: const Text('Bắt đầu ngay ↗'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty State ("Bạn chưa có đơn hàng nào!")
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
                backgroundColor: AppColors.violet,
                foregroundColor: Colors.white,
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

/// Offline Banner & Local GPS Queue Card (Theo phong cách .wallet-sync nghienai.click)
class OfflineQueueBanner extends StatelessWidget {
  final AppStateStore store;

  const OfflineQueueBanner({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    if (!store.isOfflineMode) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.gold,
        border: Border.all(color: AppColors.ink, width: 1.6),
        boxShadow: const [
          BoxShadow(
            color: AppColors.pink,
            offset: Offset(7, 7),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.ink,
              border: Border.all(color: AppColors.ink),
            ),
            child: Text(
              'OFFLINE QUEUE • Mất kết nối mạng internet. Tọa độ đang được lưu tạm (${store.offlineQueueCount} bản ghi SQLite)',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.acid,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFamily: 'Consolas',
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.ink, width: 1.5),
            ),
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 44,
                      color: AppColors.ink,
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.add_location_alt_outlined,
                      size: 28,
                      color: AppColors.violet,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Mất kết nối mạng\ninternet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Đừng lo lắng! Tọa độ GPS và thao tác của bạn đang được lưu tạm trên máy. Vui lòng kiểm tra lại 4G/Wi-Fi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ink,
                      foregroundColor: AppColors.acid,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    onPressed: () => store.toggleOfflineSimulation(false),
                    child: const Text(
                      'Thử kết nối lại ↗',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmer Skeleton Loading List
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
                  decoration: const BoxDecoration(
                    color: AppColors.shimmerBase,
                    borderRadius: BorderRadius.all(Radius.zero),
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
                        decoration: const BoxDecoration(
                          color: AppColors.shimmerBase,
                          borderRadius: BorderRadius.all(Radius.zero),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: AppColors.shimmerHighlight,
                          borderRadius: BorderRadius.all(Radius.zero),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 100,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: AppColors.shimmerBase,
                          borderRadius: BorderRadius.all(Radius.zero),
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

/// Bản đồ Tương tác Google Maps Web Mercator (EPSG:3857) + Phối cảnh 3D Navigation 60 FPS
class Map3dPerspectiveWidget extends StatefulWidget {
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
  final MapViewMode mode;
  final bool showTopBanner;
  final String? pickupLabel;
  final String? dropoffLabel;

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
    this.mode = MapViewMode.driverTurnByTurn,
    this.showTopBanner = true,
    this.pickupLabel,
    this.dropoffLabel,
  });

  @override
  State<Map3dPerspectiveWidget> createState() => _Map3dPerspectiveWidgetState();
}

class _Map3dPerspectiveWidgetState extends State<Map3dPerspectiveWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  double _cameraYawOffset = 0.0;
  double _cameraPitchOffset = 0.0;
  int _zoomLevel = 14;
  Offset _panPixelOffset = Offset.zero;
  String _googleLayer = 'm'; // 'm': Bản đồ, 'm,traffic': Giao thông, 'y': Vệ tinh

  bool get _isAutomatedTestBinding {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTest');
  }

  @override
  void initState() {
    super.initState();
    _zoomLevel = widget.mode == MapViewMode.fleetOverview ? 13 : 14;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    if (!_isAutomatedTestBinding) {
      _animController.repeat();
    } else {
      _animController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  static double _lonToWorldX(double lon, int zoom) {
    final mapSize = 256.0 * (1 << zoom);
    return ((lon + 180.0) / 360.0) * mapSize;
  }

  static double _latToWorldY(double lat, int zoom) {
    final mapSize = 256.0 * (1 << zoom);
    final sinLat = math.sin(lat * math.pi / 180.0).clamp(-0.9999, 0.9999);
    final mercN = math.log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * math.pi);
    return (0.5 - mercN) * mapSize;
  }

  GeoPoint _resolveCenterGeo(List<GeoPoint> effectiveRoute) {
    if (widget.mode == MapViewMode.fleetOverview) {
      final drivers = AppStateStore.instance.drivers;
      if (drivers.isNotEmpty) {
        double sumLat = 0;
        double sumLng = 0;
        for (final d in drivers) {
          sumLat += d.location.latitude;
          sumLng += d.location.longitude;
        }
        return GeoPoint(
          latitude: sumLat / drivers.length,
          longitude: sumLng / drivers.length,
        );
      }
    }
    if (effectiveRoute.isNotEmpty) {
      double minLat = effectiveRoute.first.latitude;
      double maxLat = effectiveRoute.first.latitude;
      double minLng = effectiveRoute.first.longitude;
      double maxLng = effectiveRoute.first.longitude;
      for (final pt in effectiveRoute) {
        minLat = math.min(minLat, pt.latitude);
        maxLat = math.max(maxLat, pt.latitude);
        minLng = math.min(minLng, pt.longitude);
        maxLng = math.max(maxLng, pt.longitude);
      }
      return GeoPoint(
        latitude: (minLat + maxLat) * 0.5,
        longitude: (minLng + maxLng) * 0.5,
      );
    }
    return const GeoPoint(latitude: 10.7769, longitude: 106.7009);
  }

  Widget _buildGoogleMapTileLayer(Size viewSize, GeoPoint centerGeo) {
    if (_isAutomatedTestBinding ||
        viewSize.width <= 0 ||
        viewSize.height <= 0) {
      return const SizedBox.shrink();
    }
    final maxTileIndex = (1 << _zoomLevel) - 1;
    final centerWorldX =
        _lonToWorldX(centerGeo.longitude, _zoomLevel) - _panPixelOffset.dx;
    final centerWorldY =
        _latToWorldY(centerGeo.latitude, _zoomLevel) - _panPixelOffset.dy;

    final topLeftWorldX = centerWorldX - viewSize.width * 0.5;
    final topLeftWorldY = centerWorldY - viewSize.height * 0.5;
    final bottomRightWorldX = centerWorldX + viewSize.width * 0.5;
    final bottomRightWorldY = centerWorldY + viewSize.height * 0.5;

    final minTileX = (topLeftWorldX / 256.0).floor();
    final maxTileX = (bottomRightWorldX / 256.0).floor();
    final minTileY = (topLeftWorldY / 256.0).floor();
    final maxTileY = (bottomRightWorldY / 256.0).floor();

    final tiles = <Widget>[];
    for (var ty = minTileY; ty <= maxTileY; ty++) {
      if (ty < 0 || ty > maxTileIndex) continue;
      for (var tx = minTileX; tx <= maxTileX; tx++) {
        final wrappedTx = ((tx % (maxTileIndex + 1)) + (maxTileIndex + 1)) %
            (maxTileIndex + 1);
        final left = tx * 256.0 - topLeftWorldX;
        final top = ty * 256.0 - topLeftWorldY;
        final tileUrl = EnvConfig.buildGoogleMapTileUrl(
          x: wrappedTx,
          y: ty,
          z: _zoomLevel,
          layer: _googleLayer,
        );
        tiles.add(
          Positioned(
            key: ValueKey('ggtile_${_googleLayer}_${_zoomLevel}_${wrappedTx}_$ty'),
            left: left,
            top: top,
            width: 256.5,
            height: 256.5,
            child: Image.network(
              tileUrl,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        );
      }
    }
    return Stack(clipBehavior: Clip.hardEdge, children: tiles);
  }

  IconData _topBannerIcon() {
    switch (widget.mode) {
      case MapViewMode.customerPreview:
        return Icons.route_rounded;
      case MapViewMode.customerLiveTracking:
        return Icons.share_location_rounded;
      case MapViewMode.driverRadar:
        return Icons.radar_rounded;
      case MapViewMode.fleetOverview:
        return Icons.hub_rounded;
      case MapViewMode.driverTurnByTurn:
        return Icons.turn_right;
    }
  }

  String _topBannerSubtitle(int pointCount) {
    switch (widget.mode) {
      case MapViewMode.customerPreview:
        return 'Google Maps Route • $pointCount điểm tọa độ • ${widget.roadName}';
      case MapViewMode.customerLiveTracking:
        return 'Định vị trực tiếp Google Maps • $pointCount điểm GPS • ${widget.roadName}';
      case MapViewMode.driverRadar:
        return 'Google Maps Radar • Quét đơn bán kính 3km - 8km • ${widget.roadName}';
      case MapViewMode.fleetOverview:
        return 'Google Maps Fleet • Giám sát ${AppStateStore.instance.drivers.length} tài xế trực tuyến';
      case MapViewMode.driverTurnByTurn:
        return widget.is3dMode
            ? 'Góc nhìn 3D Pitch 55° • $pointCount điểm GPS • ${widget.roadName}'
            : 'Chế độ 2D Overview • $pointCount điểm GPS • ${widget.roadName}';
    }
  }

  bool get _shouldShowSpeedometer =>
      widget.mode == MapViewMode.driverTurnByTurn ||
      widget.mode == MapViewMode.customerLiveTracking;

  @override
  Widget build(BuildContext context) {
    final effectiveRoute = widget.routePoints.length >= 2
        ? widget.routePoints
        : AppStateStore.instance.activeRoutePolyline;
    final centerGeo = _resolveCenterGeo(effectiveRoute);
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final adaptiveHeight = viewportHeight > 0
        ? (viewportHeight * (widget.height / 860.0)).clamp(185.0, 460.0)
        : widget.height;
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.zero),
      child: SizedBox(
        height: adaptiveHeight,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
            return MouseRegion(
              onHover: (event) {
                if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
                  return;
                }
                final nx =
                    (event.localPosition.dx / constraints.maxWidth - 0.5) * 2.0;
                final ny =
                    (event.localPosition.dy / constraints.maxHeight - 0.5) *
                        2.0;
                setState(() {
                  _cameraYawOffset = (nx * 0.045).clamp(-0.06, 0.06);
                  _cameraPitchOffset = (-ny * 0.035).clamp(-0.05, 0.05);
                });
              },
              onExit: (_) {
                setState(() {
                  _cameraYawOffset = 0.0;
                  _cameraPitchOffset = 0.0;
                });
              },
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _panPixelOffset += details.delta;
                  });
                },
                onTapUp: widget.onTapRelativePoint == null
                    ? null
                    : (details) {
                        final relX = (details.localPosition.dx /
                                constraints.maxWidth)
                            .clamp(0.0, 1.0);
                        final relY = (details.localPosition.dy /
                                constraints.maxHeight)
                            .clamp(0.0, 1.0);
                        widget.onTapRelativePoint!(Offset(relX, relY));
                      },
                child: AnimatedBuilder(
                  animation: _animController,
                  builder: (context, _) {
                    final phase = _animController.value;
                    final matrix = Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateX(widget.is3dMode ? _cameraPitchOffset : 0.0)
                      ..rotateY(widget.is3dMode ? _cameraYawOffset : 0.0);

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Transform(
                            alignment: Alignment.center,
                            transform: matrix,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CustomPaint(
                                  painter: _Map3dCanvasPainter(
                                    is3dMode: widget.is3dMode,
                                    progressFraction: widget.progressFraction,
                                    drawnPolygonPoints:
                                        widget.drawnPolygonPoints,
                                    routePoints: effectiveRoute,
                                    animPhase: phase,
                                    mode: widget.mode,
                                    zoomLevel: _zoomLevel,
                                    panPixelOffset: _panPixelOffset,
                                    centerGeo: centerGeo,
                                    drawBackgroundOnly: true,
                                    pickupLabel: widget.pickupLabel,
                                    dropoffLabel: widget.dropoffLabel,
                                    fleetDrivers:
                                        AppStateStore.instance.drivers,
                                  ),
                                ),
                                _buildGoogleMapTileLayer(viewSize, centerGeo),
                                CustomPaint(
                                  painter: _Map3dCanvasPainter(
                                    is3dMode: widget.is3dMode,
                                    progressFraction: widget.progressFraction,
                                    drawnPolygonPoints:
                                        widget.drawnPolygonPoints,
                                    routePoints: effectiveRoute,
                                    animPhase: phase,
                                    mode: widget.mode,
                                    zoomLevel: _zoomLevel,
                                    panPixelOffset: _panPixelOffset,
                                    centerGeo: centerGeo,
                                    drawBackgroundOnly: false,
                                    pickupLabel: widget.pickupLabel,
                                    dropoffLabel: widget.dropoffLabel,
                                    fleetDrivers:
                                        AppStateStore.instance.drivers,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (widget.showTopBanner)
                          Positioned(
                            top: 10,
                            left: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.darkSidebar.withValues(
                                  alpha: 0.90,
                                ),
                                borderRadius:
                                    const BorderRadius.all(Radius.zero),
                                border: Border.all(
                                  color: AppColors.routeRibbonFill.withValues(
                                    alpha: 0.55,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _topBannerIcon(),
                                    color: AppColors.surface,
                                    size: 24,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.nextTurnInstruction,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.surface,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          _topBannerSubtitle(
                                            effectiveRoute.length,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_shouldShowSpeedometer)
                          Positioned(
                            top: widget.showTopBanner ? 72 : 12,
                            right: 12,
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.darkSidebar,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.danger,
                                  width: 2.2,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    widget.speedKmh.toStringAsFixed(0),
                                    style: const TextStyle(
                                      color: AppColors.surface,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const Text(
                                    'km/h',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 8.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Bộ chuyển lớp bản đồ Google Maps (Bản đồ / Giao thông / Vệ tinh)
                        Positioned(
                          bottom: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.darkSidebar.withValues(
                                alpha: 0.88,
                              ),
                              border: Border.all(
                                color: Colors.white24,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.map_outlined,
                                  size: 13,
                                  color: AppColors.acid,
                                ),
                                const SizedBox(width: 4),
                                _buildLayerChip('m', 'Bản đồ'),
                                const SizedBox(width: 3),
                                _buildLayerChip('m,traffic', 'Giao thông'),
                                const SizedBox(width: 3),
                                _buildLayerChip('y', 'Vệ tinh'),
                              ],
                            ),
                          ),
                        ),
                        // Cụm nút điều khiển Zoom +/-, Recenter & 2D/3D
                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildMapControlBtn(
                                label: '+',
                                tooltip: 'Phóng to Google Maps',
                                onTap: () {
                                  setState(() {
                                    _zoomLevel = (_zoomLevel + 1).clamp(11, 18);
                                  });
                                },
                              ),
                              const SizedBox(height: 4),
                              _buildMapControlBtn(
                                label: '−',
                                tooltip: 'Thu nhỏ Google Maps',
                                onTap: () {
                                  setState(() {
                                    _zoomLevel = (_zoomLevel - 1).clamp(11, 18);
                                  });
                                },
                              ),
                              const SizedBox(height: 4),
                              _buildMapControlBtn(
                                icon: Icons.my_location,
                                tooltip: 'Căn giữa lộ trình',
                                onTap: () {
                                  setState(() {
                                    _panPixelOffset = Offset.zero;
                                  });
                                },
                              ),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: widget.onToggle3d,
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    color: AppColors.surface,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    widget.is3dMode ? '3D' : '2D',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLayerChip(String layerCode, String title) {
    final active = _googleLayer == layerCode;
    return InkWell(
      onTap: () => setState(() => _googleLayer = layerCode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        color: active ? AppColors.primary : Colors.transparent,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
            color: active ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildMapControlBtn({
    String? label,
    IconData? icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
              ),
            ],
          ),
          child: icon != null
              ? Icon(icon, size: 16, color: AppColors.ink)
              : Text(
                  label ?? '',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
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
  final double animPhase;
  final MapViewMode mode;
  final int zoomLevel;
  final Offset panPixelOffset;
  final GeoPoint centerGeo;
  final bool drawBackgroundOnly;
  final String? pickupLabel;
  final String? dropoffLabel;
  final List<DriverApplicantRecord> fleetDrivers;

  const _Map3dCanvasPainter({
    required this.is3dMode,
    required this.progressFraction,
    required this.drawnPolygonPoints,
    required this.routePoints,
    required this.animPhase,
    required this.mode,
    required this.zoomLevel,
    required this.panPixelOffset,
    required this.centerGeo,
    required this.drawBackgroundOnly,
    required this.pickupLabel,
    required this.dropoffLabel,
    required this.fleetDrivers,
  });

  Offset _projectSingleGeoPoint(GeoPoint pt, Size size) {
    final centerWorldX =
        _Map3dPerspectiveWidgetState._lonToWorldX(centerGeo.longitude, zoomLevel);
    final centerWorldY =
        _Map3dPerspectiveWidgetState._latToWorldY(centerGeo.latitude, zoomLevel);
    final ptWorldX =
        _Map3dPerspectiveWidgetState._lonToWorldX(pt.longitude, zoomLevel);
    final ptWorldY =
        _Map3dPerspectiveWidgetState._latToWorldY(pt.latitude, zoomLevel);

    final rawX = size.width * 0.5 + (ptWorldX - centerWorldX) + panPixelOffset.dx;
    final rawY = size.height * 0.5 + (ptWorldY - centerWorldY) + panPixelOffset.dy;
    return Offset(
      rawX.clamp(24.0, math.max(25.0, size.width - 24.0)),
      rawY.clamp(28.0, math.max(29.0, size.height - 28.0)),
    );
  }

  /// Chiếu danh sách tọa độ địa lý (vĩ độ, kinh độ) thực tế lên không gian khung vẽ Web Mercator (EPSG:3857)
  List<Offset> _projectGeoPointsToCanvas(Size size) {
    if (routePoints.length < 2) {
      return [
        Offset(size.width * 0.28, size.height * 0.78),
        Offset(size.width * 0.50, size.height * 0.52),
        Offset(size.width * 0.72, size.height * 0.28),
      ];
    }
    return routePoints.map((pt) => _projectSingleGeoPoint(pt, size)).toList();
  }

  void _drawCalloutBadge(
    Canvas canvas,
    Offset anchor,
    String text,
    Color bgColor, {
    Offset offset = const Offset(0, -24),
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 130);

    final badgeRect = Rect.fromCenter(
      center: anchor + offset,
      width: tp.width + 12,
      height: tp.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
      Paint()..color = bgColor.withValues(alpha: 0.92),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    tp.paint(
      canvas,
      Offset(badgeRect.left + 6, badgeRect.top + 3),
    );
  }

  void _drawExtruded3dBuilding(
    Canvas canvas,
    Rect footprint,
    double height3d,
    double animAngle,
  ) {
    final roofRect = footprint.shift(Offset(0, -height3d));

    final frontWall = Path()
      ..moveTo(roofRect.left, roofRect.bottom)
      ..lineTo(roofRect.right, roofRect.bottom)
      ..lineTo(footprint.right, footprint.bottom)
      ..lineTo(footprint.left, footprint.bottom)
      ..close();
    canvas.drawPath(
      frontWall,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF334155).withValues(alpha: 0.72),
            const Color(0xFF1E293B).withValues(alpha: 0.72),
          ],
        ).createShader(Rect.fromPoints(roofRect.topLeft, footprint.bottomRight)),
    );

    canvas.drawRect(
      roofRect,
      Paint()..color = const Color(0xFF1E293B).withValues(alpha: 0.75),
    );
    canvas.drawRect(
      roofRect,
      Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final animAngle = animPhase * math.pi * 2.0;

    if (drawBackgroundOnly) {
      // Nền dự phòng Vector Map khi chưa tải xong tile hoặc chạy kiểm thử widget
      final skyHeight = is3dMode ? size.height * 0.16 : 0.0;
      if (is3dMode) {
        final skyRect = Rect.fromLTWH(0, 0, size.width, skyHeight);
        canvas.drawRect(
          skyRect,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            ).createShader(skyRect),
        );
      }

      final groundRect =
          Rect.fromLTWH(0, skyHeight, size.width, size.height - skyHeight);
      canvas.drawRect(
        groundRect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
          ).createShader(groundRect),
      );

      final gridPaint = Paint()
        ..color = const Color(0xFF94A3B8).withValues(alpha: 0.35)
        ..strokeWidth = 1.0;
      for (int i = 1; i <= 6; i++) {
        final t = i / 7.0;
        final y = skyHeight + (size.height - skyHeight) * t;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
      for (int i = -3; i <= 3; i++) {
        final topX = size.width * (0.5 + i * (is3dMode ? 0.08 : 0.14));
        final botX = size.width * (0.5 + i * 0.18);
        canvas.drawLine(
          Offset(topX, skyHeight),
          Offset(botX, size.height),
          gridPaint,
        );
      }
      return;
    }

    // Lớp phủ Vector Overlay trên nền Google Maps Tiles
    if (is3dMode && mode == MapViewMode.driverTurnByTurn) {
      final buildings = <(Rect, double)>[
        (Rect.fromLTWH(size.width * 0.05, size.height * 0.46, 62, 70), 22.0),
        (Rect.fromLTWH(size.width * 0.76, size.height * 0.38, 68, 76), 24.0),
      ];
      for (final b in buildings) {
        _drawExtruded3dBuilding(canvas, b.$1, b.$2, animAngle);
      }
    }

    // Vẽ đa giác vùng Geofence tùy chỉnh nếu có
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

    // Chiếu lộ trình tọa độ GPS thực tế lên dải Route Ribbon (#00B4D8 với viền #0077B6)
    final casingPaint = Paint()
      ..color = AppColors.routeRibbonCasing
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final ribbonPaint = Paint()
      ..color = AppColors.routeRibbonFill
      ..strokeWidth = 7
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

    // Các hạt xung năng lượng chạy dọc tuyến lộ trình ở 60 FPS
    final totalSegments = screenPts.length - 1;
    if (totalSegments >= 1) {
      for (int pIdx = 0; pIdx < 3; pIdx++) {
        final pulseT = (animPhase + pIdx / 3.0) % 1.0;
        final exactSeg = pulseT * totalSegments;
        final sIdx = exactSeg.floor().clamp(0, totalSegments - 1);
        final localT = (exactSeg - sIdx).clamp(0.0, 1.0);
        final pulsePt =
            Offset.lerp(screenPts[sIdx], screenPts[sIdx + 1], localT)!;
        canvas.drawCircle(
          pulsePt,
          5.5,
          Paint()
            ..color = const Color(0xFF00F5D4).withValues(alpha: 0.78)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        canvas.drawCircle(
          pulsePt,
          2.5,
          Paint()..color = Colors.white,
        );
      }
    }

    // Cột mốc [A] Điểm lấy hàng & [B] Điểm giao hàng kèm nhãn Callout trực quan
    final beaconPulse = (math.sin(animAngle * 2.0) + 1.0) * 0.5;
    canvas.drawCircle(
      screenPts.first,
      9 + 4 * beaconPulse,
      Paint()..color = AppColors.primary.withValues(alpha: 0.30),
    );
    canvas.drawCircle(screenPts.first, 6.5, Paint()..color = AppColors.primary);
    _drawCalloutBadge(
      canvas,
      screenPts.first,
      pickupLabel ?? '[A] Điểm lấy',
      AppColors.primary,
      offset: const Offset(0, -18),
    );

    canvas.drawCircle(
      screenPts.last,
      10 + 4 * beaconPulse,
      Paint()..color = AppColors.accent.withValues(alpha: 0.34),
    );
    canvas.drawCircle(screenPts.last, 7.5, Paint()..color = AppColors.accent);
    _drawCalloutBadge(
      canvas,
      screenPts.last,
      dropoffLabel ?? '[B] Điểm giao',
      AppColors.accent,
      offset: const Offset(0, -18),
    );

    // Chế độ Fleet Overview: Hiển thị toàn bộ đội xe đa tài xế trên bản đồ Google Maps
    if (mode == MapViewMode.fleetOverview && fleetDrivers.isNotEmpty) {
      for (var i = 0; i < fleetDrivers.length; i++) {
        final drv = fleetDrivers[i];
        final drvOffset = _projectSingleGeoPoint(drv.location, size);
        final statusColor =
            drv.isOnline ? AppColors.success : AppColors.textSecondary;
        canvas.drawCircle(
          drvOffset,
          12,
          Paint()..color = statusColor.withValues(alpha: 0.25),
        );
        canvas.drawCircle(
          drvOffset,
          7.5,
          Paint()..color = statusColor,
        );
        canvas.drawCircle(
          drvOffset,
          3.0,
          Paint()..color = Colors.white,
        );
        _drawCalloutBadge(
          canvas,
          drvOffset,
          drv.fullName.split(' ').last,
          statusColor,
          offset: Offset(0, i.isEven ? -18 : 18),
        );
      }
      return;
    }

    // Chế độ Customer Preview: Không vẽ xe tài xế giả định khi chưa đặt đơn
    if (mode == MapViewMode.customerPreview) {
      return;
    }

    // Nội suy vị trí biểu tượng xe Tài xế dọc theo lộ trình thực tế
    final t = progressFraction.clamp(0.0, 1.0);
    final exactIdx = t * totalSegments;
    final segIdx = exactIdx.floor().clamp(0, totalSegments - 1);
    final segT = (exactIdx - segIdx).clamp(0.0, 1.0);
    final driverCenter =
        Offset.lerp(screenPts[segIdx], screenPts[segIdx + 1], segT)!;

    final radarRadius =
        (mode == MapViewMode.driverRadar ? 22.0 : 14.0) + 14.0 * animPhase;
    canvas.drawCircle(
      driverCenter,
      radarRadius,
      Paint()
        ..color = AppColors.success.withValues(alpha: (1.0 - animPhase) * 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    canvas.drawCircle(
      driverCenter,
      15,
      Paint()..color = AppColors.success.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      driverCenter,
      9.5,
      Paint()..color = AppColors.success,
    );
    canvas.drawCircle(
      driverCenter,
      3.8,
      Paint()..color = Colors.white,
    );
    _drawCalloutBadge(
      canvas,
      driverCenter,
      mode == MapViewMode.driverRadar ? 'Vị trí của bạn' : 'Tài xế',
      AppColors.success,
      offset: const Offset(0, 18),
    );
  }

  @override
  bool shouldRepaint(covariant _Map3dCanvasPainter oldDelegate) =>
      oldDelegate.is3dMode != is3dMode ||
      oldDelegate.progressFraction != progressFraction ||
      oldDelegate.animPhase != animPhase ||
      oldDelegate.mode != mode ||
      oldDelegate.zoomLevel != zoomLevel ||
      oldDelegate.panPixelOffset != panPixelOffset ||
      oldDelegate.drawBackgroundOnly != drawBackgroundOnly ||
      oldDelegate.drawnPolygonPoints.length != drawnPolygonPoints.length ||
      oldDelegate.routePoints.length != routePoints.length;
}
