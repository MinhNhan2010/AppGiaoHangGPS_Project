import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'animated_3d_ui_icons.dart';

class _StudioPolygonMarkClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.72)
      ..lineTo(size.width * 0.72, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class StudioMarkWordmark extends StatelessWidget {
  final bool light;
  final String title;
  final String suffix;
  final String badgeTag;

  const StudioMarkWordmark({
    super.key,
    this.light = true,
    this.title = 'Giao Hàng Siêu Tốc',
    this.suffix = '.vn',
    this.badgeTag = 'GHST',
  });

  @override
  Widget build(BuildContext context) {
    final markBg = light ? AppColors.acid : AppColors.ink;
    final markFg = light ? AppColors.techBg : Colors.white;
    final leftBarColor = light ? AppColors.violet : AppColors.acid;
    final tagColor = light ? AppColors.violet : AppColors.acid;
    final wordColor = light ? Colors.white : AppColors.ink;
    final suffixColor = light ? AppColors.acid : AppColors.violet;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipPath(
          clipper: _StudioPolygonMarkClipper(),
          child: Container(
            width: 40,
            height: 40,
            color: markBg,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 5,
                  child: ColoredBox(color: leftBarColor),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'G',
                      style: TextStyle(
                        color: markFg,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.0,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 5,
                  child: Text(
                    badgeTag,
                    style: TextStyle(
                      color: tagColor,
                      fontSize: 6.5,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Consolas',
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 11),
        Flexible(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(
                  text: title,
                  style: TextStyle(
                    color: wordColor,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.1,
                    height: 1.0,
                  ),
                ),
                TextSpan(
                  text: suffix,
                  style: TextStyle(
                    color: suffixColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Consolas',
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class StudioKicker extends StatelessWidget {
  final String label;
  final Color textColor;
  final Color barColor;

  const StudioKicker({
    super.key,
    required this.label,
    this.textColor = AppColors.techMuted,
    this.barColor = AppColors.pink,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 2,
          color: barColor,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'Consolas',
              letterSpacing: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class StudioCapabilityRail extends StatelessWidget {
  final List<String> items;

  const StudioCapabilityRail({
    super.key,
    this.items = const [
      'Định vị GPS Realtime',
      'Điều phối Smart Dispatch 28s',
      'Định tuyến OSRM & Haversine',
      'Đối soát Ví & VietQR EMVCo',
      'Đồng bộ 16 bảng SQLite',
    ],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 44,
      decoration: const BoxDecoration(
        color: AppColors.acid,
        border: Border(
          top: BorderSide(color: AppColors.techBg, width: 1.2),
          bottom: BorderSide(color: AppColors.techBg, width: 1.2),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(items.length, (index) {
            final idxLabel = '0${index + 1}';
            return Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: const BoxDecoration(
                border: Border(
                  right: BorderSide(color: Color(0x4D080B0F), width: 1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    idxLabel,
                    style: const TextStyle(
                      color: AppColors.violet,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Consolas',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    items[index].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.techBg,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.north_east_rounded,
                    size: 14,
                    color: AppColors.techBg,
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

class StudioTechGridPainter extends CustomPainter {
  final double gridSize;
  final Color lineColor;

  const StudioTechGridPainter({
    this.gridSize = 38.0,
    this.lineColor = const Color(0x1494A0AE),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0;

    for (double x = 0; x <= size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final glowCenter = Offset(size.width * 0.80, size.height * 0.30);
    final glowRadius = size.width * 0.36;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.violet.withValues(alpha: 0.22),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius));
    canvas.drawCircle(glowCenter, glowRadius, glowPaint);
  }

  @override
  bool shouldRepaint(covariant StudioTechGridPainter oldDelegate) => false;
}

class StudioSvgAssemblyBlueprint extends StatelessWidget {
  final int totalUsers;
  final int totalOrders;
  final int totalDrivers;

  const StudioSvgAssemblyBlueprint({
    super.key,
    required this.totalUsers,
    required this.totalOrders,
    required this.totalDrivers,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 310,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E14),
        border: Border.all(color: AppColors.techLine, width: 1.2),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: const StudioTechGridPainter(gridSize: 28),
            ),
          ),
          // Thanh tiêu đề trên cùng (.svg-assembly-head)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 36,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.techLine)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'GIAOHANG_GPS / ARCHITECTURE',
                    style: TextStyle(
                      color: AppColors.techMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Consolas',
                      letterSpacing: 1.1,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 12,
                        color: AppColors.acid,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'ĐỒNG BỘ 16 BẢNG SQLITE',
                        style: TextStyle(
                          color: AppColors.acid,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Consolas',
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 4 Mảnh phân hệ ở 4 góc (.svg-fragment-1..4)
          Positioned(
            top: 48,
            left: 14,
            child: _buildFragmentBox(
              index: '01',
              title: 'KHÁCH HÀNG',
              icon: Icons.shopping_bag_outlined,
              accent: AppColors.pink,
            ),
          ),
          Positioned(
            top: 48,
            right: 14,
            child: _buildFragmentBox(
              index: '02',
              title: 'TÀI XẾ GPS',
              icon: Icons.two_wheeler_rounded,
              accent: const Color(0xFF9C83FF),
            ),
          ),
          Positioned(
            bottom: 48,
            left: 14,
            child: _buildFragmentBox(
              index: '03',
              title: 'CỬA HÀNG B2B',
              icon: Icons.storefront_outlined,
              accent: AppColors.acid,
            ),
          ),
          Positioned(
            bottom: 48,
            right: 14,
            child: _buildFragmentBox(
              index: '04',
              title: 'GO-MAU ADMIN',
              icon: Icons.shield_outlined,
              accent: const Color(0xFF4EDCFF),
            ),
          ),
          // Khối lõi trung tâm (.svg-assembly-core)
          Center(
            child: Container(
              width: 196,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E14),
                border: Border.all(color: AppColors.acid, width: 1.3),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.violet,
                    offset: Offset(8, 8),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.hub_outlined,
                        color: AppColors.acid,
                        size: 30,
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.all(5),
                        color: AppColors.pink,
                        child: const Icon(
                          Icons.my_location_rounded,
                          size: 14,
                          color: AppColors.techBg,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'OSRM + POSTGIS + SQLITE',
                    style: TextStyle(
                      color: AppColors.techMuted,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Consolas',
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'ĐIỀU PHỐI THỜI GIAN THỰC',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.verified_rounded,
                        size: 13,
                        color: AppColors.acid,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '$totalOrders ĐƠN • $totalDrivers TX • $totalUsers USER',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.acid,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Consolas',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Thanh chân sơ đồ (.svg-assembly-foot)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 34,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.techLine)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '04 PHÂN HỆ ĐỘC LẬP • GIAO HÀNG SIÊU TỐC',
                    style: TextStyle(
                      color: AppColors.techMuted,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Consolas',
                    ),
                  ),
                  Text(
                    'SẴN SÀNG',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Consolas',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFragmentBox({
    required String index,
    required String title,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      width: 112,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xF00A0E14),
        border: Border.all(color: const Color(0x42D2E5F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                index,
                style: const TextStyle(
                  color: AppColors.techMuted,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Consolas',
                ),
              ),
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Consolas',
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

/// Màn hình Hoạt ảnh Khởi động 3D Đa thành phần 60 FPS xuất hiện mỗi khi mở ứng dụng
class Studio3dStartupSplashScreen extends StatefulWidget {
  final VoidCallback onCompleted;
  final Duration duration;
  final bool forceContinuousInTest;

  const Studio3dStartupSplashScreen({
    super.key,
    required this.onCompleted,
    this.duration = const Duration(milliseconds: 3400),
    this.forceContinuousInTest = false,
  });

  @override
  State<Studio3dStartupSplashScreen> createState() =>
      _Studio3dStartupSplashScreenState();
}

class _Studio3dStartupSplashScreenState
    extends State<Studio3dStartupSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _pointerTiltX = -0.10;
  double _pointerTiltY = 0.14;
  bool _completedTriggered = false;

  bool get _isAutomatedTestBinding {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTest');
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_completedTriggered) {
        _completedTriggered = true;
        widget.onCompleted();
      }
    });
    if (!_isAutomatedTestBinding || widget.forceContinuousInTest) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSkip() {
    if (_completedTriggered) return;
    _completedTriggered = true;
    _controller.stop();
    widget.onCompleted();
  }

  void _update3dStageTilt(Offset localPosition, Size stageSize) {
    if (stageSize.width <= 0 || stageSize.height <= 0) return;
    final normX = ((localPosition.dx - stageSize.width / 2) /
            (stageSize.width / 2))
        .clamp(-1.0, 1.0);
    final normY = ((localPosition.dy - stageSize.height / 2) /
            (stageSize.height / 2))
        .clamp(-1.0, 1.0);
    setState(() {
      _pointerTiltY = normX * 0.28;
      _pointerTiltX = -normY * 0.24;
    });
  }

  String _bootPhaseLabel(double progress) {
    if (progress < 0.34) {
      return 'GHST EXPRESS • ĐANG KHỞI TẠO HỆ THỐNG ĐỊNH VỊ 3D...';
    }
    if (progress < 0.72) {
      return 'GHST EXPRESS • ĐANG TẢI BẢN ĐỒ & DỊCH VỤ GIAO NHẬN...';
    }
    return 'GIAO HÀNG SIÊU TỐC (GHST) SẴN SÀNG!';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.techBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stageSize = Size(constraints.maxWidth, constraints.maxHeight);
            return MouseRegion(
              onHover: (e) => _update3dStageTilt(e.localPosition, stageSize),
              onExit: (_) {
                setState(() {
                  _pointerTiltX = -0.10;
                  _pointerTiltY = 0.14;
                });
              },
              child: GestureDetector(
                onPanUpdate: (d) =>
                    _update3dStageTilt(d.localPosition, stageSize),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final progress = _controller.value.clamp(0.0, 1.0);
                    final waveAngle = progress * math.pi * 4.0;
                    final dynamicTiltX =
                        _pointerTiltX + math.sin(waveAngle) * 0.06;
                    final dynamicTiltY =
                        _pointerTiltY + math.cos(waveAngle) * 0.08;
                    final floatY = math.sin(waveAngle) * -8.0;

                    final matrix3d = Matrix4.identity()
                      ..setEntry(3, 2, 0.0016)
                      ..translateByDouble(0.0, floatY, 0.0, 1.0)
                      ..rotateX(dynamicTiltX)
                      ..rotateY(dynamicTiltY);

                    final percent = (progress * 100).round();

                    return Stack(
                      children: [
                        const Positioned.fill(
                          child: CustomPaint(
                            painter: StudioTechGridPainter(gridSize: 34),
                          ),
                        ),
                        // Nút Bỏ qua nhanh góc phải trên
                        Positioned(
                          top: 18,
                          right: 22,
                          child: InkWell(
                            onTap: _handleSkip,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.techPanel,
                                border: Border.all(
                                  color: AppColors.acid,
                                  width: 1.4,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: AppColors.violet,
                                    offset: Offset(4, 4),
                                    blurRadius: 0,
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'BỎ QUA 3D INTRO',
                                    style: TextStyle(
                                      color: AppColors.acid,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      fontFamily: 'Consolas',
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(
                                    Icons.north_east_rounded,
                                    color: AppColors.acid,
                                    size: 14,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.symmetric(
                              horizontal: (constraints.maxWidth * 0.05)
                                  .clamp(14.0, 48.0),
                              vertical: (constraints.maxHeight * 0.03)
                                  .clamp(14.0, 32.0),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const StudioMarkWordmark(light: true),
                                const SizedBox(height: 14),
                                Transform(
                                  alignment: Alignment.center,
                                  transform: matrix3d,
                                  child: Container(
                                    width: (constraints.maxWidth * 0.76)
                                        .clamp(240.0, 620.0),
                                    height: (constraints.maxHeight * 0.36)
                                        .clamp(180.0, 360.0),
                                    decoration: BoxDecoration(
                                      color: const Color(0xCC0A0E14),
                                      border: Border.all(
                                        color: AppColors.acid,
                                        width: 1.6,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: AppColors.violet,
                                          offset: Offset(12, 12),
                                          blurRadius: 0,
                                        ),
                                      ],
                                    ),
                                    child: CustomPaint(
                                      painter: Studio3dBootScenePainter(
                                        phase: progress,
                                        tiltX: dynamicTiltX,
                                        tiltY: dynamicTiltY,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                Wrap(
                                  spacing: 18,
                                  runSpacing: 12,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    Animated3dIconBadge(
                                      style: Icon3dStyle.scooterExpress,
                                      size: 62,
                                      isSelected: progress >= 0.15,
                                    ),
                                    Animated3dIconBadge(
                                      style: Icon3dStyle.parcelBox,
                                      size: 62,
                                      isSelected: progress >= 0.40,
                                    ),
                                    Animated3dIconBadge(
                                      style: Icon3dStyle.gpsPinRadar,
                                      size: 62,
                                      isSelected: progress >= 0.65,
                                    ),
                                    Animated3dIconBadge(
                                      style: Icon3dStyle.walletVault,
                                      size: 62,
                                      isSelected: progress >= 0.85,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 22),
                                Container(
                                  width: (constraints.maxWidth * 0.80)
                                      .clamp(240.0, 640.0),
                                  padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppColors.paper,
                                      border: Border.all(
                                        color: AppColors.ink,
                                        width: 2.0,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: AppColors.violet,
                                          offset: Offset(6, 6),
                                          blurRadius: 0,
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _bootPhaseLabel(progress),
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: AppColors.ink,
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w900,
                                                  fontFamily: 'Consolas',
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2,
                                              ),
                                              color: AppColors.ink,
                                              child: Text(
                                                '$percent%',
                                                style: const TextStyle(
                                                  color: AppColors.acid,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w900,
                                                  fontFamily: 'Consolas',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Container(
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            border: Border.all(
                                              color: AppColors.ink,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: FractionallySizedBox(
                                            alignment: Alignment.centerLeft,
                                            widthFactor:
                                                progress.clamp(0.04, 1.0),
                                            child: Container(
                                              color: AppColors.acid,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
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
}

/// Động cơ vẽ Cảnh 3D Khởi động: Lưới mặt phẳng Radar 3D, Khối kiện hàng 3D xoay đa diện, Vòng quỹ đạo Vệ tinh GPS & Chùm tia Laser Volumetric
class Studio3dBootScenePainter extends CustomPainter {
  final double phase;
  final double tiltX;
  final double tiltY;

  const Studio3dBootScenePainter({
    required this.phase,
    this.tiltX = 0.0,
    this.tiltY = 0.0,
  });

  Offset _project3D(
    double x,
    double y,
    double z,
    Offset center,
    double yaw,
    double pitch,
  ) {
    // Xoay quanh trục Y (Yaw)
    final cosY = math.cos(yaw);
    final sinY = math.sin(yaw);
    final x1 = x * cosY - z * sinY;
    final z1 = x * sinY + z * cosY;

    // Xoay quanh trục X (Pitch)
    final cosP = math.cos(pitch);
    final sinP = math.sin(pitch);
    final y2 = y * cosP - z1 * sinP;
    final z2 = y * sinP + z1 * cosP;

    // Phép chiếu phối cảnh (Perspective Projection)
    const fov = 420.0;
    final scale = fov / (fov + z2 + 240.0);
    return Offset(center.dx + x1 * scale, center.dy + y2 * scale);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.54);
    final yaw = phase * math.pi * 2.0 + tiltY * 1.4;
    final pitch = 0.52 + tiltX * 0.8;

    // 1. Vẽ quầng sáng Volumetric trung tâm
    final bgGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.violet.withValues(alpha: 0.42),
          AppColors.acid.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: size.width * 0.44));
    canvas.drawCircle(center, size.width * 0.44, bgGlow);

    // 2. Vẽ mặt phẳng lưới đô thị 3D & sóng xung kích Radar ở độ sâu y = 68
    const floorY = 68.0;
    final gridPaint = Paint()
      ..color = const Color(0x38D1E7FF)
      ..strokeWidth = 1.0;

    for (int i = -4; i <= 4; i++) {
      final coord = i * 34.0;
      final p1 = _project3D(coord, floorY, -136.0, center, yaw * 0.35, pitch);
      final p2 = _project3D(coord, floorY, 136.0, center, yaw * 0.35, pitch);
      canvas.drawLine(p1, p2, gridPaint);

      final q1 = _project3D(-136.0, floorY, coord, center, yaw * 0.35, pitch);
      final q2 = _project3D(136.0, floorY, coord, center, yaw * 0.35, pitch);
      canvas.drawLine(q1, q2, gridPaint);
    }

    // 3 vòng sóng Radar 3D lan tỏa trên mặt phẳng
    for (int r = 0; r < 3; r++) {
      final ringPhase = (phase * 2.0 + r * 0.33) % 1.0;
      final radius = 24.0 + ringPhase * 125.0;
      final ringPaint = Paint()
        ..color = (r.isEven ? AppColors.acid : AppColors.pink)
            .withValues(alpha: (1.0 - ringPhase) * 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final ringPath = Path();
      const segments = 36;
      for (int s = 0; s <= segments; s++) {
        final theta = (s / segments) * math.pi * 2.0;
        final rx = math.cos(theta) * radius;
        final rz = math.sin(theta) * radius;
        final pt = _project3D(rx, floorY, rz, center, yaw * 0.35, pitch);
        if (s == 0) {
          ringPath.moveTo(pt.dx, pt.dy);
        } else {
          ringPath.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(ringPath, ringPaint);
    }

    // 3. Vẽ 2 Vòng quỹ đạo Vệ tinh GPS 3D nghiêng chéo
    for (int orbitIdx = 0; orbitIdx < 2; orbitIdx++) {
      final orbitTilt = orbitIdx == 0 ? 0.45 : -0.45;
      final orbitRadius = orbitIdx == 0 ? 108.0 : 92.0;
      final orbitPaint = Paint()
        ..color = (orbitIdx == 0 ? AppColors.acid : AppColors.violet)
            .withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;

      final orbitPath = Path();
      const segs = 40;
      for (int s = 0; s <= segs; s++) {
        final a = (s / segs) * math.pi * 2.0;
        final ox = math.cos(a) * orbitRadius;
        final oy = math.sin(a) * orbitRadius * math.sin(orbitTilt) - 12.0;
        final oz = math.sin(a) * orbitRadius * math.cos(orbitTilt);
        final pt = _project3D(ox, oy, oz, center, yaw * 0.5, pitch);
        if (s == 0) {
          orbitPath.moveTo(pt.dx, pt.dy);
        } else {
          orbitPath.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(orbitPath, orbitPaint);

      // Hạt vệ tinh GPS chuyển động trên quỹ đạo
      final satAngle = phase * math.pi * 4.0 + (orbitIdx * math.pi);
      final sx = math.cos(satAngle) * orbitRadius;
      final sy = math.sin(satAngle) * orbitRadius * math.sin(orbitTilt) - 12.0;
      final sz = math.sin(satAngle) * orbitRadius * math.cos(orbitTilt);
      final satPt = _project3D(sx, sy, sz, center, yaw * 0.5, pitch);

      canvas.drawCircle(
        satPt,
        8.0,
        Paint()
          ..color = (orbitIdx == 0 ? AppColors.acid : AppColors.pink)
              .withValues(alpha: 0.35),
      );
      canvas.drawCircle(
        satPt,
        4.2,
        Paint()..color = orbitIdx == 0 ? AppColors.acid : AppColors.pink,
      );
    }

    // 4. Vẽ Khối Lập Phương Kiện Hàng 3D (Isometric 3D Parcel Cube) bay lơ lửng ở trung tâm
    final floatOffset = math.sin(phase * math.pi * 4.0) * 10.0 - 16.0;
    const half = 36.0;
    final vertices = <List<double>>[
      [-half, floatOffset - half, -half], // 0: top-left-back
      [half, floatOffset - half, -half], // 1: top-right-back
      [half, floatOffset - half, half], // 2: top-right-front
      [-half, floatOffset - half, half], // 3: top-left-front
      [-half, floatOffset + half, -half], // 4: bottom-left-back
      [half, floatOffset + half, -half], // 5: bottom-right-back
      [half, floatOffset + half, half], // 6: bottom-right-front
      [-half, floatOffset + half, half], // 7: bottom-left-front
    ];

    final projected = vertices
        .map((v) => _project3D(v[0], v[1], v[2], center, yaw, pitch))
        .toList();

    final faces = <(List<int>, Color)>[
      ([4, 5, 6, 7], const Color(0xFF1E1A34)), // Mặt đáy
      ([0, 1, 5, 4], const Color(0xFF3A2399)), // Mặt sau
      ([0, 3, 7, 4], const Color(0xFF492BC4)), // Mặt trái
      ([1, 2, 6, 5], const Color(0xFF5B33E6)), // Mặt phải
      ([3, 2, 6, 7], const Color(0xFF724DFF)), // Mặt trước
      ([0, 1, 2, 3], AppColors.paper), // Mặt nắp trên
    ];

    final edgePaint = Paint()
      ..color = AppColors.acid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    for (final face in faces) {
      final idxs = face.$1;
      final path = Path()
        ..moveTo(projected[idxs[0]].dx, projected[idxs[0]].dy)
        ..lineTo(projected[idxs[1]].dx, projected[idxs[1]].dy)
        ..lineTo(projected[idxs[2]].dx, projected[idxs[2]].dy)
        ..lineTo(projected[idxs[3]].dx, projected[idxs[3]].dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = face.$2.withValues(alpha: 0.90)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(path, edgePaint);
    }

    // Dải băng niêm phong 3D màu Acid Lime cắt ngang nắp hộp
    final tapeStart = Offset.lerp(projected[0], projected[3], 0.5)!;
    final tapeEnd = Offset.lerp(projected[1], projected[2], 0.5)!;
    canvas.drawLine(
      tapeStart,
      tapeEnd,
      Paint()
        ..color = AppColors.pink
        ..strokeWidth = 5.0,
    );

    // 5. Chùm tia Laser Volumetric quét dọc khối 3D
    final scanRatio = (math.sin(phase * math.pi * 4.0) + 1.0) / 2.0;
    final scanY = floatOffset - half + scanRatio * (half * 2.0);
    final scanPts = [
      _project3D(-half * 1.25, scanY, -half * 1.25, center, yaw, pitch),
      _project3D(half * 1.25, scanY, -half * 1.25, center, yaw, pitch),
      _project3D(half * 1.25, scanY, half * 1.25, center, yaw, pitch),
      _project3D(-half * 1.25, scanY, half * 1.25, center, yaw, pitch),
    ];
    final scanPath = Path()
      ..moveTo(scanPts[0].dx, scanPts[0].dy)
      ..lineTo(scanPts[1].dx, scanPts[1].dy)
      ..lineTo(scanPts[2].dx, scanPts[2].dy)
      ..lineTo(scanPts[3].dx, scanPts[3].dy)
      ..close();
    canvas.drawPath(
      scanPath,
      Paint()
        ..color = AppColors.acid.withValues(alpha: 0.28)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      scanPath,
      Paint()
        ..color = AppColors.acid
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // 6. Đỉnh Ghim Định vị GPS 3D phát sáng phía trên khối hộp
    final pinCenter = _project3D(
      0,
      floatOffset - half - 32.0,
      0,
      center,
      yaw,
      pitch,
    );
    canvas.drawCircle(
      pinCenter,
      14.0,
      Paint()..color = AppColors.pink.withValues(alpha: 0.30),
    );
    canvas.drawCircle(
      pinCenter,
      7.0,
      Paint()..color = AppColors.pink,
    );
    canvas.drawCircle(
      pinCenter,
      3.0,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant Studio3dBootScenePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.tiltX != tiltX ||
        oldDelegate.tiltY != tiltY;
  }
}

/// Nền Đồ họa Bản đồ Lộ trình GPS 3D Chìm cho Màn hình Đăng nhập (Ambient 3D Isometric City & Live GPS Route Network)
class Studio3dLoginAmbientMapPainter extends CustomPainter {
  final double phase;
  final double parallaxX;
  final double parallaxY;

  const Studio3dLoginAmbientMapPainter({
    this.phase = 0.35,
    this.parallaxX = 0.0,
    this.parallaxY = 0.0,
  });

  Offset _projectWorld3D(
    double x,
    double y,
    double z,
    Size size,
  ) {
    final center = Offset(
      size.width * 0.5 + parallaxX * 28.0,
      size.height * 0.54 + parallaxY * 20.0,
    );
    final yaw = 0.32 + math.sin(phase * math.pi * 2.0) * 0.06 + parallaxX * 0.12;
    final pitch = 0.56 + parallaxY * 0.08;

    final cosY = math.cos(yaw);
    final sinY = math.sin(yaw);
    final x1 = x * cosY - z * sinY;
    final z1 = x * sinY + z * cosY;

    final cosP = math.cos(pitch);
    final sinP = math.sin(pitch);
    final y2 = y * cosP - z1 * sinP;
    final z2 = y * sinP + z1 * cosP;

    const fov = 780.0;
    final depth = (fov + z2 + 420.0).clamp(120.0, 3000.0);
    final scale = fov / depth;
    return Offset(center.dx + x1 * scale, center.dy + y2 * scale);
  }

  void _drawExtruded3dBlock(
    Canvas canvas,
    Size size, {
    required double cx,
    required double cz,
    required double w,
    required double d,
    required double h,
    required Color strokeColor,
    required Color topFillColor,
  }) {
    const groundY = 120.0;
    final topY = groundY - h;

    final b0 = _projectWorld3D(cx - w, groundY, cz - d, size);
    final b1 = _projectWorld3D(cx + w, groundY, cz - d, size);
    final b2 = _projectWorld3D(cx + w, groundY, cz + d, size);
    final b3 = _projectWorld3D(cx - w, groundY, cz + d, size);

    final t0 = _projectWorld3D(cx - w, topY, cz - d, size);
    final t1 = _projectWorld3D(cx + w, topY, cz - d, size);
    final t2 = _projectWorld3D(cx + w, topY, cz + d, size);
    final t3 = _projectWorld3D(cx - w, topY, cz + d, size);

    final topPath = Path()
      ..moveTo(t0.dx, t0.dy)
      ..lineTo(t1.dx, t1.dy)
      ..lineTo(t2.dx, t2.dy)
      ..lineTo(t3.dx, t3.dy)
      ..close();

    final frontPath = Path()
      ..moveTo(t3.dx, t3.dy)
      ..lineTo(t2.dx, t2.dy)
      ..lineTo(b2.dx, b2.dy)
      ..lineTo(b3.dx, b3.dy)
      ..close();

    final sidePath = Path()
      ..moveTo(t1.dx, t1.dy)
      ..lineTo(t2.dx, t2.dy)
      ..lineTo(b2.dx, b2.dy)
      ..lineTo(b1.dx, b1.dy)
      ..close();

    canvas.drawPath(
      frontPath,
      Paint()
        ..color = strokeColor.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      sidePath,
      Paint()
        ..color = strokeColor.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      topPath,
      Paint()
        ..color = topFillColor
        ..style = PaintingStyle.fill,
    );

    final wirePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawPath(topPath, wirePaint);
    canvas.drawLine(t0, b0, wirePaint);
    canvas.drawLine(t1, b1, wirePaint);
    canvas.drawLine(t2, b2, wirePaint);
    canvas.drawLine(t3, b3, wirePaint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Hai quầng sáng chiều sâu đối xứng (Dual Radial Volumetric Glow)
    final topRightGlow = Offset(size.width * 0.82, size.height * 0.22);
    canvas.drawCircle(
      topRightGlow,
      size.width * 0.38,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.violet.withValues(alpha: 0.26),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: topRightGlow, radius: size.width * 0.38),
        ),
    );

    final bottomLeftGlow = Offset(size.width * 0.18, size.height * 0.80);
    canvas.drawCircle(
      bottomLeftGlow,
      size.width * 0.34,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.acid.withValues(alpha: 0.12),
            AppColors.violet.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(
          Rect.fromCircle(center: bottomLeftGlow, radius: size.width * 0.34),
        ),
    );

    // 2. Lưới mặt phẳng bản đồ phối cảnh 3D (3D Ground Grid)
    const groundY = 120.0;
    final gridPaint = Paint()
      ..color = const Color(0x1694A0AE)
      ..strokeWidth = 1.0;

    for (int i = -9; i <= 9; i++) {
      final coord = i * 85.0;
      final p1 = _projectWorld3D(coord, groundY, -765.0, size);
      final p2 = _projectWorld3D(coord, groundY, 765.0, size);
      canvas.drawLine(p1, p2, gridPaint);

      final q1 = _projectWorld3D(-765.0, groundY, coord, size);
      final q2 = _projectWorld3D(765.0, groundY, coord, size);
      canvas.drawLine(q1, q2, gridPaint);
    }

    // 3. Các khối tòa nhà 3D Wireframe ở hai bên cánh (Tạo chiều sâu đô thị 3D)
    const buildingSpecs = <(double, double, double, double, double, bool)>[
      (-480, -220, 42, 42, 95, true),
      (-360, -90, 36, 36, 64, false),
      (-520, 80, 48, 38, 120, false),
      (-340, 230, 40, 40, 78, true),
      (360, -240, 44, 40, 110, false),
      (490, -70, 46, 46, 135, true),
      (370, 120, 38, 38, 72, false),
      (510, 240, 42, 42, 92, true),
    ];

    for (final b in buildingSpecs) {
      _drawExtruded3dBlock(
        canvas,
        size,
        cx: b.$1,
        cz: b.$2,
        w: b.$3,
        d: b.$4,
        h: b.$5,
        strokeColor: b.$6
            ? AppColors.acid.withValues(alpha: 0.22)
            : const Color(0x33D1E7FF),
        topFillColor: b.$6
            ? AppColors.acid.withValues(alpha: 0.06)
            : AppColors.violet.withValues(alpha: 0.08),
      );
    }

    // 4. Vòng sóng Radar 3D lan tỏa tại 2 trạm điều phối hai bên
    final radarNodes = <(double, double, Color)>[
      (-410.0, 20.0, AppColors.acid),
      (420.0, -20.0, AppColors.pink),
    ];

    for (final node in radarNodes) {
      for (int r = 0; r < 2; r++) {
        final rp = (phase * 1.5 + r * 0.5) % 1.0;
        final radius = 26.0 + rp * 150.0;
        final ringPath = Path();
        const segs = 32;
        for (int s = 0; s <= segs; s++) {
          final a = (s / segs) * math.pi * 2.0;
          final pt = _projectWorld3D(
            node.$1 + math.cos(a) * radius,
            groundY,
            node.$2 + math.sin(a) * radius,
            size,
          );
          if (s == 0) {
            ringPath.moveTo(pt.dx, pt.dy);
          } else {
            ringPath.lineTo(pt.dx, pt.dy);
          }
        }
        canvas.drawPath(
          ringPath,
          Paint()
            ..color = node.$3.withValues(alpha: (1.0 - rp) * 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // 5. Ba tuyến lộ trình giao hàng GPS 3D & Hạt tín hiệu Tài xế di chuyển
    final routes = <(List<(double, double)>, Color)>[
      (
        [
          (-640, 260),
          (-410, 20),
          (-180, -140),
          (190, -180),
          (420, -20),
          (640, 190),
        ],
        AppColors.acid,
      ),
      (
        [
          (-620, -240),
          (-340, -120),
          (-110, 150),
          (230, 170),
          (490, -70),
          (660, -220),
        ],
        AppColors.violet,
      ),
      (
        [
          (-480, 340),
          (-260, 210),
          (40, 240),
          (340, 120),
          (580, -140),
        ],
        AppColors.pink,
      ),
    ];

    for (int rIdx = 0; rIdx < routes.length; rIdx++) {
      final waypoints = routes[rIdx].$1;
      final color = routes[rIdx].$2;
      final projectedPts = waypoints
          .map((wp) => _projectWorld3D(wp.$1, groundY - 2.0, wp.$2, size))
          .toList();

      final routePath = Path()
        ..moveTo(projectedPts.first.dx, projectedPts.first.dy);
      for (int i = 1; i < projectedPts.length; i++) {
        routePath.lineTo(projectedPts[i].dx, projectedPts[i].dy);
      }

      // Quầng sáng đường dẫn
      canvas.drawPath(
        routePath,
        Paint()
          ..color = color.withValues(alpha: 0.14)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.0,
      );
      canvas.drawPath(
        routePath,
        Paint()
          ..color = color.withValues(alpha: 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );

      // Tính vị trí hạt tín hiệu GPS chạy dọc lộ trình 3D
      final tGlobal = (phase + rIdx * 0.31) % 1.0;
      final totalSegs = waypoints.length - 1;
      final scaledT = tGlobal * totalSegs;
      final segIdx = scaledT.floor().clamp(0, totalSegs - 1);
      final localT = scaledT - segIdx;

      final wx = waypoints[segIdx].$1 +
          (waypoints[segIdx + 1].$1 - waypoints[segIdx].$1) * localT;
      final wz = waypoints[segIdx].$2 +
          (waypoints[segIdx + 1].$2 - waypoints[segIdx].$2) * localT;

      final groundBeacon = _projectWorld3D(wx, groundY - 2.0, wz, size);
      final skyBeacon = _projectWorld3D(wx, groundY - 46.0, wz, size);

      // Cột sáng định vị 3D (3D Vertical Telemetry Pillar)
      canvas.drawLine(
        groundBeacon,
        skyBeacon,
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(
        groundBeacon,
        9.0,
        Paint()..color = color.withValues(alpha: 0.25),
      );
      canvas.drawCircle(
        groundBeacon,
        4.0,
        Paint()..color = color,
      );
      canvas.drawCircle(
        skyBeacon,
        3.2,
        Paint()..color = Colors.white,
      );
    }

    // 6. Bốn dấu chữ thập ngắm tọa độ ở 4 góc màn hình (Corner HUD Crosshairs)
    final crossPaint = Paint()
      ..color = const Color(0x45D1E7FF)
      ..strokeWidth = 1.2;
    const margin = 26.0;
    const arm = 8.0;
    final corners = [
      const Offset(margin, margin),
      Offset(size.width - margin, margin),
      Offset(margin, size.height - margin),
      Offset(size.width - margin, size.height - margin),
    ];
    for (final c in corners) {
      canvas.drawLine(
        Offset(c.dx - arm, c.dy),
        Offset(c.dx + arm, c.dy),
        crossPaint,
      );
      canvas.drawLine(
        Offset(c.dx, c.dy - arm),
        Offset(c.dx, c.dy + arm),
        crossPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant Studio3dLoginAmbientMapPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.parallaxX != parallaxX ||
        oldDelegate.parallaxY != parallaxY;
  }
}


