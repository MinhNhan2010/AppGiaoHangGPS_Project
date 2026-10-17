import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Phân loại các mẫu Icon 3D AI sử dụng xuyên suốt 4 phân hệ ứng dụng
enum Icon3dStyle {
  /// Xe máy giao hàng Hỏa tốc 30 phút 3D (Onboarding & UC03 Express)
  scooterExpress(
    assetPath: 'assets/icons_3d/scooter_express_3d.png',
    primaryColor: AppColors.accent,
    secondaryColor: AppColors.primary,
    glowColor: AppColors.routeRibbonFill,
    fallbackIcon: Icons.delivery_dining,
    label: '3D Express',
  ),

  /// Thùng kiện hàng tiêu chuẩn niêm phong 3D (UC03 Standard & UC32/UC33)
  parcelBox(
    assetPath: 'assets/icons_3d/parcel_box_3d.png',
    primaryColor: AppColors.primary,
    secondaryColor: AppColors.accent,
    glowColor: AppColors.success,
    fallbackIcon: Icons.inventory_2_rounded,
    label: '3D Parcel',
  ),

  /// Ghim định vị GPS & Sóng Radar 3D (UC07, UC15 Nhận cuốc 28s & UC16)
  gpsPinRadar(
    assetPath: 'assets/icons_3d/gps_pin_radar_3d.png',
    primaryColor: AppColors.routeRibbonFill,
    secondaryColor: AppColors.primary,
    glowColor: AppColors.accent,
    fallbackIcon: Icons.radar_rounded,
    label: '3D GPS Radar',
  ),

  /// Ví thu nhập & Két bảo mật ký quỹ 3D (UC19 Ví Tài xế & UC38 Ví COD)
  walletVault(
    assetPath: 'assets/icons_3d/wallet_vault_3d.png',
    primaryColor: AppColors.success,
    secondaryColor: AppColors.primary,
    glowColor: AppColors.warning,
    fallbackIcon: Icons.account_balance_wallet_rounded,
    label: '3D Wallet',
  );

  final String assetPath;
  final Color primaryColor;
  final Color secondaryColor;
  final Color glowColor;
  final IconData fallbackIcon;
  final String label;

  const Icon3dStyle({
    required this.assetPath,
    required this.primaryColor,
    required this.secondaryColor,
    required this.glowColor,
    required this.fallbackIcon,
    required this.label,
  });
}

/// Widget hiển thị Biểu tượng 3D AI kèm hiệu ứng chuyển động Phối cảnh 3D (Matrix4 Tilt, Floating & Radar Ripple)
class Animated3dIconBadge extends StatefulWidget {
  final Icon3dStyle style;
  final double size;
  final bool showRadarPulse;
  final bool isSelected;
  final VoidCallback? onTap;

  const Animated3dIconBadge({
    super.key,
    required this.style,
    this.size = 76,
    this.showRadarPulse = true,
    this.isSelected = false,
    this.onTap,
  });

  @override
  State<Animated3dIconBadge> createState() => _Animated3dIconBadgeState();
}

class _Animated3dIconBadgeState extends State<Animated3dIconBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _pointerTiltX = -0.14;
  double _pointerTiltY = 0.18;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant Animated3dIconBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSelected != widget.isSelected ||
        oldWidget.style != widget.style) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateTiltFromLocalOffset(Offset localPosition) {
    final half = widget.size / 2.0;
    if (half <= 0) return;
    final normX = ((localPosition.dx - half) / half).clamp(-1.0, 1.0);
    final normY = ((localPosition.dy - half) / half).clamp(-1.0, 1.0);
    setState(() {
      _pointerTiltY = normX * 0.38;
      _pointerTiltX = -normY * 0.38;
    });
  }

  void _trigger3dPulseWave() {
    _controller.forward(from: 0.0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) => _updateTiltFromLocalOffset(event.localPosition),
      onExit: (_) {
        setState(() {
          _pointerTiltX = -0.14;
          _pointerTiltY = 0.18;
        });
      },
      child: GestureDetector(
        onPanUpdate: (details) =>
            _updateTiltFromLocalOffset(details.localPosition),
        onTap: _trigger3dPulseWave,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            // Dao động nổi 3D theo hàm điều hòa tắt dần (floating elevation)
            final wave = math.sin(t * math.pi * 2.0) * (1.0 - t * 0.45);
            final floatOffsetY = -5.5 * wave - (widget.isSelected ? 3.0 : 0.0);
            final dynamicTiltX = _pointerTiltX + 0.16 * wave;
            final dynamicTiltY = _pointerTiltY + 0.22 * math.sin(t * math.pi);

            final transform3d = Matrix4.identity()
              ..setEntry(3, 2, 0.0018)
              ..translateByDouble(0.0, floatOffsetY, 0.0, 1.0)
              ..rotateX(dynamicTiltX)
              ..rotateY(dynamicTiltY);

            final shadowScale = (1.0 - (floatOffsetY.abs() / 36.0)).clamp(
              0.72,
              1.0,
            );

            return SizedBox(
              width: widget.size,
              height: widget.size + 14,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Vòng sóng Radar 3D lan tỏa dưới chân khối biểu tượng
                  if (widget.showRadarPulse)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RadarPulse3dPainter(
                          progress: t,
                          color: widget.style.glowColor,
                        ),
                      ),
                    ),
                  // Bóng đổ 3D co giãn động theo độ cao lơ lửng của vật thể
                  Positioned(
                    bottom: 2,
                    child: Transform.scale(
                      scaleX: shadowScale,
                      scaleY: shadowScale * 0.42,
                      child: Container(
                        width: widget.size * 0.68,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: widget.style.secondaryColor.withValues(
                                alpha: 0.32 * shadowScale,
                              ),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Khối cầu/hộp Isometric 3D có ánh sáng Specular & tài nguyên AI 3D
                  Transform(
                    alignment: Alignment.center,
                    transform: transform3d,
                    child: Container(
                      width: widget.size * 0.84,
                      height: widget.size * 0.84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: const Alignment(-0.35, -0.42),
                          radius: 0.95,
                          colors: [
                            Colors.white,
                            widget.style.primaryColor.withValues(alpha: 0.88),
                            widget.style.secondaryColor,
                          ],
                          stops: const [0.0, 0.52, 1.0],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.85),
                          width: widget.isSelected ? 2.6 : 1.6,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.style.primaryColor.withValues(
                              alpha: 0.42,
                            ),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Hiển thị ảnh Icon 3D do AI sinh ra từ assets/icons_3d/ và tự động dự phòng bằng lớp vẽ 3D Isometric nếu chưa nạp tệp
                            Image.asset(
                              widget.style.assetPath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) {
                                return CustomPaint(
                                  painter: _Isometric3dBadgeSurfacePainter(
                                    primary: widget.style.primaryColor,
                                    secondary: widget.style.secondaryColor,
                                    glow: widget.style.glowColor,
                                  ),
                                  child: Center(
                                    child: Icon(
                                      widget.style.fallbackIcon,
                                      size: widget.size * 0.44,
                                      color: AppColors.surface,
                                    ),
                                  ),
                                );
                              },
                            ),
                            // Lớp phản xạ gương Specular Highlight phía trên bên trái tạo độ bóng khối 3D
                            Positioned(
                              top: widget.size * 0.06,
                              left: widget.size * 0.12,
                              child: Container(
                                width: widget.size * 0.28,
                                height: widget.size * 0.14,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.white.withValues(alpha: 0.65),
                                      Colors.white.withValues(alpha: 0.0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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

class _RadarPulse3dPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _RadarPulse3dPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.46);
    final maxRadius = size.width * 0.50;

    for (var ring = 0; ring < 2; ring++) {
      final p = ((progress + ring * 0.45) % 1.0).clamp(0.0, 1.0);
      final radius = maxRadius * (0.55 + 0.45 * p);
      final alpha = ((1.0 - p) * 0.55).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: radius * 2.0,
          height: radius * 1.45,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPulse3dPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _Isometric3dBadgeSurfacePainter extends CustomPainter {
  final Color primary;
  final Color secondary;
  final Color glow;

  const _Isometric3dBadgeSurfacePainter({
    required this.primary,
    required this.secondary,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.34;

    // Vẽ mặt phẳng đế lục giác Isometric 3D tạo chiều sâu
    final hexPath = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (i * 60 - 30) * math.pi / 180.0;
      final pt = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * 0.78 * math.sin(angle),
      );
      if (i == 0) {
        hexPath.moveTo(pt.dx, pt.dy);
      } else {
        hexPath.lineTo(pt.dx, pt.dy);
      }
    }
    hexPath.close();

    canvas.drawPath(
      hexPath,
      Paint()
        ..color = secondary.withValues(alpha: 0.45)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      hexPath,
      Paint()
        ..color = glow.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant _Isometric3dBadgeSurfacePainter oldDelegate) =>
      false;
}
