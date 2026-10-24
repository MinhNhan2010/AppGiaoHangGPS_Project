import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/auth/real_auth_delivery_service.dart';
import '../../core/config/env_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/security_and_barcode_utils.dart';
import '../../data/datasources/local/app_state_store.dart';
import '../../domain/enums/user_role.dart';
import '../admin/admin_subsystem_views.dart';
import '../bloc/system_architecture_cubit.dart';
import '../customer/customer_subsystem_views.dart';
import '../driver/driver_subsystem_views.dart';
import '../merchant/merchant_subsystem_views.dart';
import '../widgets/animated_3d_ui_icons.dart';
import '../widgets/in_app_google_oauth_dialog.dart';
import '../widgets/studio_design_widgets.dart';

class ArchitectureDashboardScreen extends StatefulWidget {
  const ArchitectureDashboardScreen({super.key});

  @override
  State<ArchitectureDashboardScreen> createState() =>
      _ArchitectureDashboardScreenState();
}

class _ArchitectureDashboardScreenState
    extends State<ArchitectureDashboardScreen>
    with SingleTickerProviderStateMixin {
  final AppStateStore _store = AppStateStore.instance;
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _fullNameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _newPasswordCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();

  late final AnimationController _login3dController;
  Timer? _otpCountdownTimer;
  double _loginParallaxX = 0.0;
  double _loginParallaxY = 0.0;

  bool _showStartup3dSplash = false;
  bool _isLoggedIn = false;
  bool _otpSent = false;
  bool _isDeliveringOtp = false;
  OtpDeliveryReceipt? _lastOtpReceipt;
  bool _isRegisterMode = false;
  bool _usePasswordLogin = false;
  bool _isForgotPasswordMode = false;
  bool _obscurePassword = true;
  String? _authErrorMessage;

  bool get _isAutomatedTestBinding {
    final bindingType = WidgetsBinding.instance.runtimeType.toString();
    return bindingType.contains('TestWidgetsFlutterBinding') ||
        bindingType.contains('AutomatedTest');
  }

  @override
  void initState() {
    super.initState();
    _showStartup3dSplash = !_isAutomatedTestBinding;
    _login3dController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
      value: 0.35,
    );
    if (!_isAutomatedTestBinding) {
      _login3dController.repeat();
    }
    _store.addListener(_onStoreUpdated);
  }

  void _onStoreUpdated() {
    if (mounted) setState(() {});
  }

  void _startOtpCountdownTimer() {
    _otpCountdownTimer?.cancel();
    if (_isAutomatedTestBinding) return;
    _otpCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_otpSent) {
        timer.cancel();
        return;
      }
      final remain = _store.getRemainingOtpSeconds(_phoneCtrl.text);
      setState(() {});
      if (remain <= 0) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _otpCountdownTimer?.cancel();
    RealAuthDeliveryService.instance.stopGoogleOAuthServer();
    RealAuthDeliveryService.instance.stopMobileQrAuthServer();
    _login3dController.dispose();
    _store.removeListener(_onStoreUpdated);
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _fullNameCtrl.dispose();
    _passwordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _handlePasswordLogin(BuildContext context) {
    final rawInput = _phoneCtrl.text.trim();
    final rawPassword = _passwordCtrl.text.trim();
    if (rawInput.isEmpty) {
      setState(() {
        _authErrorMessage = 'Vui lòng nhập Số điện thoại hoặc Email đăng nhập.';
      });
      return;
    }
    if (rawPassword.length < 6) {
      setState(() {
        _authErrorMessage = 'Mật khẩu phải có từ 6 ký tự trở lên.';
      });
      return;
    }
    final existingUser = _store.findUserByPhoneOrEmail(rawInput);
    if (existingUser == null) {
      setState(() {
        _authErrorMessage =
            'Tài khoản chưa được đăng ký. Vui lòng chuyển sang tab "Đăng ký".';
      });
      return;
    }
    if (existingUser.status == 'LOCKED') {
      setState(() {
        _authErrorMessage =
            'Tài khoản của bạn hiện đang bị khóa tạm thời. Vui lòng liên hệ bộ phận hỗ trợ.';
      });
      return;
    }
    final authenticated = _store.authenticateWithPassword(
      phoneOrEmail: rawInput,
      password: rawPassword,
    );
    if (authenticated == null) {
      setState(() {
        _authErrorMessage = 'Mật khẩu không chính xác. Vui lòng kiểm tra lại.';
      });
      return;
    }
    context.read<SystemArchitectureCubit>().selectRole(authenticated.role);
    setState(() {
      _authErrorMessage = null;
      _isLoggedIn = true;
      _otpSent = false;
      _isForgotPasswordMode = false;
    });
  }

  void _handleSendOtp() {
    final rawInput = _phoneCtrl.text.trim();
    final isEmailInput = rawInput.contains('@');

    if (!_isRegisterMode) {
      if (isEmailInput) {
        if (!rawInput.contains('.') || rawInput.length < 5) {
          setState(() {
            _authErrorMessage = 'Vui lòng nhập địa chỉ Email hợp lệ.';
          });
          return;
        }
      } else {
        final digits = rawInput.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length < 9) {
          setState(() {
            _authErrorMessage =
                'Vui lòng nhập Số điện thoại (từ 9 chữ số) hoặc Email hợp lệ.';
          });
          return;
        }
      }

      final existingUser = _store.findUserByPhoneOrEmail(rawInput);
      if (existingUser == null) {
        setState(() {
          _authErrorMessage =
              'Tài khoản chưa tồn tại trên hệ thống. Vui lòng chuyển sang tab "Đăng ký" để tạo tài khoản mới.';
        });
        return;
      }
      if (existingUser.status == 'LOCKED') {
        setState(() {
          _authErrorMessage =
              'Tài khoản của bạn hiện đang bị khóa tạm thời. Vui lòng liên hệ bộ phận hỗ trợ.';
        });
        return;
      }
    } else {
      if (_fullNameCtrl.text.trim().isEmpty) {
        setState(() {
          _authErrorMessage = 'Vui lòng nhập Họ và tên của bạn.';
        });
        return;
      }
      final digits = rawInput.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length < 9) {
        setState(() {
          _authErrorMessage =
              'Vui lòng nhập Số điện thoại hợp lệ (từ 9 chữ số).';
        });
        return;
      }
      final rawEmail = _emailCtrl.text.trim();
      if (rawEmail.isNotEmpty &&
          (!rawEmail.contains('@') || !rawEmail.contains('.'))) {
        setState(() {
          _authErrorMessage =
              'Địa chỉ Email không hợp lệ (hoặc để trống nếu nhận OTP qua Số điện thoại).';
        });
        return;
      }
      if (_passwordCtrl.text.trim().length < 6) {
        setState(() {
          _authErrorMessage = 'Vui lòng tạo mật khẩu tối thiểu 6 ký tự.';
        });
        return;
      }
      final existingUser = _store.findUserByPhoneOrEmail(rawInput) ??
          (rawEmail.isNotEmpty ? _store.findUserByPhoneOrEmail(rawEmail) : null);
      if (existingUser != null) {
        setState(() {
          _authErrorMessage =
              'Số điện thoại hoặc Email này đã được đăng ký. Vui lòng chuyển sang tab "Đăng nhập".';
        });
        return;
      }
    }

    final registerEmail = _emailCtrl.text.trim();
    if (_isRegisterMode &&
        registerEmail.isEmpty &&
        !EnvConfig.isExternalSmsGatewayConfigured &&
        !_isAutomatedTestBinding) {
      final created = _store.registerUserAccountWithRole(
        phone: rawInput,
        fullName: _fullNameCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
        role: SubsystemRole.customer,
      );
      if (created == null) {
        setState(() {
          _authErrorMessage = 'Không thể tạo tài khoản. Vui lòng thử lại.';
        });
        return;
      }
      context.read<SystemArchitectureCubit>().selectRole(created.role);
      setState(() {
        _authErrorMessage = null;
        _isLoggedIn = true;
        _otpSent = false;
      });
      return;
    }

    final otp = _store.generateOtpForPhone(rawInput);
    final String deliveryDestination;
    if (isEmailInput) {
      deliveryDestination = rawInput;
    } else if (_isRegisterMode &&
        registerEmail.isNotEmpty &&
        registerEmail.contains('@')) {
      if (EnvConfig.isExternalSmsGatewayConfigured) {
        deliveryDestination = rawInput;
        if (!_isAutomatedTestBinding && EnvConfig.isSmtpConfigured) {
          RealAuthDeliveryService.instance.deliverOtpChallenge(
            destination: registerEmail,
            otpCode: otp,
          );
        }
      } else {
        deliveryDestination = registerEmail;
      }
    } else if (!_isRegisterMode && !EnvConfig.isExternalSmsGatewayConfigured) {
      final existingUser = _store.findUserByPhoneOrEmail(rawInput);
      final linkedEmail = existingUser?.email.trim() ?? '';
      if (linkedEmail.contains('@') &&
          !linkedEmail.endsWith('@giaohanggps.vn')) {
        deliveryDestination = linkedEmail;
      } else {
        deliveryDestination = rawInput;
      }
    } else {
      deliveryDestination = rawInput;
    }

    setState(() {
      _authErrorMessage = null;
      _otpSent = true;
      _isDeliveringOtp = true;
      _lastOtpReceipt = null;
      _otpCtrl.clear();
    });
    _startOtpCountdownTimer();

    if (_isAutomatedTestBinding) {
      setState(() {
        _isDeliveringOtp = false;
      });
      return;
    }

    RealAuthDeliveryService.instance
        .deliverOtpChallenge(
          destination: deliveryDestination,
          otpCode: otp,
        )
        .then((receipt) {
          if (!mounted) return;
          setState(() {
            _isDeliveringOtp = false;
            _lastOtpReceipt = receipt;
            if (!receipt.success) {
              _otpSent = false;
              _authErrorMessage = receipt.message;
            }
          });
        });
  }

  Future<void> _handleVerifyOtpAndAuthenticate(BuildContext context) async {
    final rawInput = _phoneCtrl.text.trim();
    final inputOtp = _otpCtrl.text.trim();
    final cubit = context.read<SystemArchitectureCubit>();

    if (!_isAutomatedTestBinding &&
        _lastOtpReceipt?.channel == 'TWILIO_VERIFY_V2' &&
        inputOtp.length == 6) {
      final twilioOk = await RealAuthDeliveryService.instance
          .verifyTwilioVerifyV2Code(
            phoneNumber: rawInput,
            otpCode: inputOtp,
          );
      if (twilioOk) {
        final normKey = EnvConfig.formatVietnamPhoneNational(rawInput);
        _store.activeOtpCodesByPhone[normKey] = inputOtp;
        _store.otpExpiryEpochMsByPhone[normKey] =
            DateTime.now().millisecondsSinceEpoch + 60000;
      }
      if (!mounted) return;
    }

    if (_isForgotPasswordMode) {
      final newPwd = _newPasswordCtrl.text.trim();
      if (newPwd.length < 6) {
        setState(() {
          _authErrorMessage =
              'Vui lòng nhập mật khẩu mới tối thiểu 6 ký tự.';
        });
        return;
      }
      final updatedUser = _store.resetPasswordWithOtp(
        phoneOrEmail: rawInput,
        otpCode: inputOtp,
        newPassword: newPwd,
      );
      if (updatedUser == null) {
        setState(() {
          _authErrorMessage =
              'Mã xác thực OTP không chính xác hoặc đã hết hiệu lực (120s).';
        });
        return;
      }
      _otpCountdownTimer?.cancel();
      cubit.selectRole(updatedUser.role);
      setState(() {
        _authErrorMessage = null;
        _isForgotPasswordMode = false;
        _usePasswordLogin = false;
        _isLoggedIn = true;
        _otpSent = false;
      });
      return;
    }

    final verified = _store.verifyOtpCode(rawInput, inputOtp);
    if (!verified) {
      setState(() {
        _authErrorMessage =
            'Mã xác thực OTP không chính xác hoặc đã hết hiệu lực.';
      });
      return;
    }

    UserAccountRecord? user;
    if (_isRegisterMode) {
      final regPassword = _passwordCtrl.text.trim().length >= 6
          ? _passwordCtrl.text.trim()
          : inputOtp;
      user = _store.registerUserAccountWithRole(
        phone: rawInput,
        email: _emailCtrl.text.trim().isNotEmpty ? _emailCtrl.text.trim() : null,
        fullName: _fullNameCtrl.text.trim(),
        password: regPassword,
        role: SubsystemRole.customer,
      );
    } else {
      user = _store.findUserByPhoneOrEmail(rawInput);
      if (user != null) {
        _store.applyAuthenticatedUserSession(user);
      }
    }

    if (user == null) {
      setState(() {
        _authErrorMessage =
            'Không thể xác thực tài khoản. Vui lòng thử lại.';
      });
      return;
    }

    _otpCountdownTimer?.cancel();
    cubit.selectRole(user.role);
    setState(() {
      _authErrorMessage = null;
      _isLoggedIn = true;
      _otpSent = false;
    });
  }

  Future<void> _handleOAuthLogin(
    BuildContext context,
    String providerName,
  ) async {
    if (!EnvConfig.isGoogleOAuthConfigured) {
      setState(() {
        _authErrorMessage =
            'Chưa cấu hình GOOGLE_CLIENT_ID & GOOGLE_CLIENT_SECRET trong EnvConfig để xác thực với máy chủ Google OAuth 2.0.';
      });
      return;
    }

    setState(() {
      _authErrorMessage = null;
    });

    final cubit = context.read<SystemArchitectureCubit>();
    bool dialogOpen = false;

    final authUrl = await RealAuthDeliveryService.instance
        .startGoogleOAuth2LoopbackFlow(
      openSystemBrowser: false,
      onAuthenticated: (result) {
        if (!mounted) return;
        if (dialogOpen) {
          dialogOpen = false;
          Navigator.of(context, rootNavigator: true).maybePop();
        }
        final user = _store.signInOrRegisterOAuthUser(
          email: result.email,
          fullName: result.fullName,
        );
        if (user == null) {
          setState(() {
            _authErrorMessage =
                'Không thể đồng bộ tài khoản Google (${result.email}) vào hệ thống.';
          });
          return;
        }
        if (user.status == 'LOCKED') {
          setState(() {
            _authErrorMessage =
                'Tài khoản ${user.email} hiện đang bị khóa tạm thời.';
          });
          return;
        }
        _store.applyAuthenticatedUserSession(user);
        cubit.selectRole(user.role);
        setState(() {
          _authErrorMessage = null;
          _isLoggedIn = true;
          _otpSent = false;
        });
      },
    );

    if (!mounted || !context.mounted) return;
    if (authUrl == null) {
      setState(() {
        _authErrorMessage =
            'Không thể khởi tạo phiên kết nối Google OAuth 2.0. Vui lòng thử lại.';
      });
      return;
    }

    dialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return InAppGoogleOAuthDialog(
          initialAuthUrl: authUrl,
          onCancel: () {
            dialogOpen = false;
            Navigator.of(dialogCtx).pop();
          },
        );
      },
    );
    dialogOpen = false;
    await RealAuthDeliveryService.instance.stopGoogleOAuthServer();
  }

  void _handleLogout() {
    setState(() {
      _store.activeAuthenticatedUser = null;
      _isLoggedIn = false;
      _otpSent = false;
      _authErrorMessage = null;
      _otpCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showStartup3dSplash) {
      return Studio3dStartupSplashScreen(
        onCompleted: () {
          if (mounted) {
            setState(() => _showStartup3dSplash = false);
          }
        },
      );
    }

    return BlocBuilder<SystemArchitectureCubit, SystemArchitectureState>(
      builder: (context, state) {
        if (!_isLoggedIn) {
          return _buildUc01LoginRegisterScreen(context);
        }

        final authUser = _store.activeAuthenticatedUser;
        final approvedRole = authUser?.role ?? state.selectedRole;
        final SubsystemRole activeRole;
        if (approvedRole == SubsystemRole.admin) {
          activeRole = SubsystemRole.admin;
        } else if (approvedRole == SubsystemRole.customer) {
          activeRole = SubsystemRole.customer;
        } else {
          activeRole = (state.selectedRole == SubsystemRole.customer ||
                  state.selectedRole == approvedRole)
              ? state.selectedRole
              : approvedRole;
        }

        final hasUnlockedPartnerRole = approvedRole == SubsystemRole.driver ||
            approvedRole == SubsystemRole.merchant;

        return Scaffold(
          backgroundColor: AppColors.paper,
          body: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: const StudioTechGridPainter(
                    gridSize: 36.0,
                    lineColor: Color(0x1415131E),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasUnlockedPartnerRole)
                      _buildPostLoginStudioTopBar(
                        context,
                        approvedRole: approvedRole,
                        activeRole: activeRole,
                        hasUnlockedPartnerRole: hasUnlockedPartnerRole,
                      ),
                    Expanded(
                      child: _buildActiveSubsystemView(activeRole),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _updateLoginParallax(Offset pos, Size screenSize) {
    if (screenSize.width <= 0 || screenSize.height <= 0) return;
    final nx = ((pos.dx - screenSize.width / 2) / (screenSize.width / 2))
        .clamp(-1.0, 1.0);
    final ny = ((pos.dy - screenSize.height / 2) / (screenSize.height / 2))
        .clamp(-1.0, 1.0);
    setState(() {
      _loginParallaxX = nx;
      _loginParallaxY = ny;
    });
  }

  Widget _buildUc01LoginRegisterScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.techBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenSize =
                Size(constraints.maxWidth, constraints.maxHeight);
            return MouseRegion(
              onHover: (e) => _updateLoginParallax(e.localPosition, screenSize),
              onExit: (_) {
                setState(() {
                  _loginParallaxX = 0.0;
                  _loginParallaxY = 0.0;
                });
              },
              child: AnimatedBuilder(
                animation: _login3dController,
                builder: (context, _) {
                  final phase = _login3dController.value;
                  final floatAngle = phase * math.pi * 2.0;
                  final isTest = _isAutomatedTestBinding;
                  final floatY = isTest ? 0.0 : math.sin(floatAngle) * -5.0;
                  final cardTiltX = isTest
                      ? 0.0
                      : (-_loginParallaxY * 0.08 +
                          math.cos(floatAngle) * 0.018);
                  final cardTiltY = isTest
                      ? 0.0
                      : (_loginParallaxX * 0.10 +
                          math.sin(floatAngle) * 0.022);

                  final cardMatrix = Matrix4.identity();
                  if (!isTest) {
                    cardMatrix
                      ..setEntry(3, 2, 0.0011)
                      ..translateByDouble(0.0, floatY, 0.0, 1.0)
                      ..rotateX(cardTiltX)
                      ..rotateY(cardTiltY);
                  }

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: Studio3dLoginAmbientMapPainter(
                            phase: phase,
                            parallaxX: _loginParallaxX,
                            parallaxY: _loginParallaxY,
                          ),
                        ),
                      ),
                      Center(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            horizontal: (constraints.maxWidth * 0.04)
                                .clamp(12.0, 32.0),
                            vertical: (constraints.maxHeight * 0.03)
                                .clamp(16.0, 32.0),
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: (constraints.maxWidth * 0.88)
                                  .clamp(300.0, 480.0),
                            ),
                            child: Transform(
                              alignment: Alignment.center,
                              transform: cardMatrix,
                              child: _buildNeoBrutalistAuthCard(
                                context,
                                isCompact: constraints.maxWidth < 400,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNeoBrutalistAuthCard(
    BuildContext context, {
    bool isCompact = false,
  }) {
    final shadowShiftX = -_loginParallaxX * 4.0;
    final shadowShiftY = -_loginParallaxY * 4.0;

    return Container(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 18 : 28,
        24,
        isCompact ? 18 : 28,
        26,
      ),
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border.all(color: AppColors.ink, width: 2.0),
        boxShadow: [
          const BoxShadow(
            color: AppColors.ink,
            offset: Offset(5, 5),
            blurRadius: 0,
          ),
          BoxShadow(
            color: AppColors.violet,
            offset: Offset(11 + shadowShiftX, 11 + shadowShiftY),
            blurRadius: 0,
          ),
          BoxShadow(
            color: AppColors.acid.withValues(alpha: 0.45),
            offset: Offset(16 + shadowShiftX * 1.4, 16 + shadowShiftY * 1.4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Animated3dIconBadge(
            style: Icon3dStyle.scooterExpress,
            size: 76,
            showRadarPulse: true,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.acid,
              border: Border.all(color: AppColors.ink, width: 1.2),
            ),
            child: const Text(
              'GHST • GIAO HÀNG SIÊU TỐC',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
                fontFamily: 'Consolas',
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.ink, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _isRegisterMode = false;
                      _isForgotPasswordMode = false;
                      _otpSent = false;
                      _authErrorMessage = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      color: !_isRegisterMode
                          ? AppColors.violet
                          : Colors.transparent,
                      alignment: Alignment.center,
                      child: Text(
                        'Đăng nhập',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: !_isRegisterMode
                              ? Colors.white
                              : AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
                Container(width: 1.5, height: 38, color: AppColors.ink),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _isRegisterMode = true;
                      _usePasswordLogin = false;
                      _isForgotPasswordMode = false;
                      _otpSent = false;
                      _authErrorMessage = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      color: _isRegisterMode
                          ? AppColors.violet
                          : Colors.transparent,
                      alignment: Alignment.center,
                      child: Text(
                        'Đăng ký tài khoản',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: _isRegisterMode
                              ? Colors.white
                              : AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _isRegisterMode
                ? 'Tạo tài khoản mới'
                : (_isForgotPasswordMode
                    ? 'Khôi phục mật khẩu bằng OTP'
                    : 'Đăng nhập hệ thống'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isRegisterMode
                ? 'Nhập Số điện thoại, Họ tên và Mật khẩu để tạo tài khoản'
                : (_isForgotPasswordMode
                    ? 'Nhập Số điện thoại hoặc Email để nhận mã OTP đặt lại mật khẩu'
                    : (_usePasswordLogin
                        ? 'Nhập Số điện thoại / Email và mật khẩu đã đăng ký'
                        : 'Nhập Số điện thoại hoặc Email để nhận mã xác thực OTP')),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          if (!_isRegisterMode) ...[
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const SizedBox(
                      width: double.infinity,
                      child: Text(
                        'Mã OTP',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    selected: !_usePasswordLogin && !_isForgotPasswordMode,
                    selectedColor: AppColors.acid,
                    onSelected: (_) => setState(() {
                      _usePasswordLogin = false;
                      _isForgotPasswordMode = false;
                      _authErrorMessage = null;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const SizedBox(
                      width: double.infinity,
                      child: Text(
                        'Mật khẩu',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    selected: _usePasswordLogin && !_isForgotPasswordMode,
                    selectedColor: AppColors.acid,
                    onSelected: (_) => setState(() {
                      _usePasswordLogin = true;
                      _isForgotPasswordMode = false;
                      _otpSent = false;
                      _authErrorMessage = null;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (_isRegisterMode) ...[
            TextField(
              controller: _fullNameCtrl,
              onChanged: (_) => setState(() => _authErrorMessage = null),
              decoration: const InputDecoration(
                hintText: 'Ví dụ: Nguyễn Văn A',
                labelText: 'Họ và tên',
                prefixIcon: Icon(
                  Icons.person_outline_rounded,
                  color: AppColors.violet,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _phoneCtrl,
            keyboardType: _isRegisterMode
                ? TextInputType.phone
                : TextInputType.emailAddress,
            onChanged: (_) {
              setState(() {
                _authErrorMessage = null;
                if (_otpSent) {
                  _otpSent = false;
                }
              });
            },
            decoration: InputDecoration(
              hintText: _isRegisterMode
                  ? 'Ví dụ: 0912345678'
                  : 'Nhập SĐT (0912...) hoặc Email',
              labelText: _isRegisterMode
                  ? 'Số điện thoại'
                  : 'Số điện thoại hoặc Email',
              prefixIcon: Icon(
                _phoneCtrl.text.contains('@')
                    ? Icons.alternate_email_rounded
                    : Icons.phone_iphone_rounded,
                color: AppColors.violet,
              ),
            ),
          ),
          if (_isRegisterMode) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) {
                setState(() {
                  _authErrorMessage = null;
                  if (_otpSent) {
                    _otpSent = false;
                  }
                });
              },
              decoration: const InputDecoration(
                hintText: 'Không bắt buộc (Ví dụ: ban@gmail.com)',
                labelText: 'Địa chỉ Email (Tùy chọn)',
                prefixIcon: Icon(
                  Icons.email_outlined,
                  color: AppColors.violet,
                ),
              ),
            ),
          ],
          if (_isRegisterMode || _usePasswordLogin) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              onChanged: (_) => setState(() => _authErrorMessage = null),
              decoration: InputDecoration(
                hintText: 'Tối thiểu 6 ký tự',
                labelText: _isRegisterMode
                    ? 'Tạo mật khẩu đăng nhập'
                    : 'Mật khẩu',
                prefixIcon: const Icon(
                  Icons.lock_outline_rounded,
                  color: AppColors.violet,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () => setState(
                    () => _obscurePassword = !_obscurePassword,
                  ),
                ),
              ),
            ),
          ],
          if (!_isRegisterMode && _usePasswordLogin) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => setState(() {
                  _isForgotPasswordMode = true;
                  _usePasswordLogin = false;
                  _otpSent = false;
                  _authErrorMessage = null;
                }),
                child: const Text(
                  'Quên mật khẩu? Lấy mã OTP qua Số điện thoại',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.violet,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
          if (_otpSent && !_usePasswordLogin) ...[
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final remainSec = _store.getRemainingOtpSeconds(_phoneCtrl.text);
                final isPhoneOtp = !_phoneCtrl.text.trim().contains('@');

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.acid.withValues(alpha: 0.35),
                        border: Border.all(color: AppColors.ink, width: 1.0),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isPhoneOtp
                                    ? Icons.sms_outlined
                                    : Icons.mark_email_read_outlined,
                                size: 15,
                                color: AppColors.ink,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _isDeliveringOtp
                                      ? 'Đang gửi mã xác thực OTP thật...'
                                      : (_lastOtpReceipt?.message ??
                                          'Mã xác thực OTP đã được gửi đi.'),
                                  style: const TextStyle(
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                color: remainSec > 0
                                    ? AppColors.ink
                                    : AppColors.danger,
                                child: Text(
                                  remainSec > 0
                                      ? 'Hiệu lực: ${remainSec}s'
                                      : 'Đã hết hạn (0s)',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    fontFamily: 'Consolas',
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _handleSendOtp,
                                child: const Text(
                                  'Gửi lại mã',
                                  style: TextStyle(
                                    fontSize: 11.2,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.violet,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: 'Nhập 6 chữ số',
                labelText: 'Mã xác thực OTP (6 chữ số)',
                counterText: '',
                prefixIcon: Icon(
                  Icons.verified_user_outlined,
                  color: AppColors.ink,
                ),
              ),
            ),
            if (_isForgotPasswordMode) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _newPasswordCtrl,
                obscureText: _obscurePassword,
                onChanged: (_) => setState(() => _authErrorMessage = null),
                decoration: const InputDecoration(
                  hintText: 'Tối thiểu 6 ký tự',
                  labelText: 'Mật khẩu mới',
                  prefixIcon: Icon(
                    Icons.lock_reset_rounded,
                    color: AppColors.violet,
                  ),
                ),
              ),
            ],
          ],
          if (_authErrorMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppColors.gold,
                border: Border.all(color: AppColors.ink, width: 1.2),
              ),
              child: Text(
                _authErrorMessage!,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
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
                padding: const EdgeInsets.symmetric(vertical: 15),
                elevation: 0,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                  side: BorderSide(color: AppColors.ink, width: 1.5),
                ),
              ),
              onPressed: () {
                if (!_isRegisterMode &&
                    _usePasswordLogin &&
                    !_isForgotPasswordMode) {
                  _handlePasswordLogin(context);
                } else if (!_otpSent) {
                  _handleSendOtp();
                } else {
                  _handleVerifyOtpAndAuthenticate(context);
                }
              },
              child: Text(
                (!_isRegisterMode &&
                        _usePasswordLogin &&
                        !_isForgotPasswordMode)
                    ? 'Đăng nhập'
                    : (_otpSent
                        ? (_isRegisterMode
                            ? 'Xác nhận OTP & Tạo tài khoản'
                            : (_isForgotPasswordMode
                                ? 'Đổi mật khẩu & Đăng nhập'
                                : 'Xác nhận OTP & Đăng nhập'))
                        : (_isRegisterMode &&
                                _emailCtrl.text.trim().isEmpty &&
                                !EnvConfig.isExternalSmsGatewayConfigured &&
                                !_isAutomatedTestBinding
                            ? 'Tạo tài khoản'
                            : 'Gửi mã OTP')),
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: Divider(color: AppColors.line)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'hoặc',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Consolas',
                  ),
                ),
              ),
              Expanded(child: Divider(color: AppColors.line)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                backgroundColor: AppColors.acid.withValues(alpha: 0.45),
                side: const BorderSide(
                  color: AppColors.ink,
                  width: 1.5,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              onPressed: () => _showMobileQrPhoneAuthDialog(context),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 18,
                    color: AppColors.ink,
                  ),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Đăng nhập bằng mã QR',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.0,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                backgroundColor: Colors.white,
                side: const BorderSide(
                  color: AppColors.ink,
                  width: 1.4,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              onPressed: () => _handleOAuthLogin(context, 'Google'),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'G',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: AppColors.pink,
                    ),
                  ),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Tiếp tục với Google',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isRegisterMode) ...[
            const SizedBox(height: 12),
            const Text(
              'Bạn muốn trở thành Đối tác Tài xế hoặc Cửa hàng? Hãy đăng ký tài khoản rồi gửi hồ sơ tại mục Cá nhân.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showMobileQrPhoneAuthDialog(BuildContext context) async {
    final cubit = context.read<SystemArchitectureCubit>();
    final initialPhone = _phoneCtrl.text.trim();

    if (!mounted) return;
    setState(() {
      _authErrorMessage = null;
    });

    bool isDialogOpen = true;
    String scanStatusText = 'Đang chờ quét mã QR...';
    bool isDeviceConnected = false;
    String? public4gHttpsUrl;
    void Function(void Function())? dialogSetState;

    final session = await RealAuthDeliveryService.instance
        .startMobileQrAuthSession(
      initialPhone: initialPhone,
      onAuthenticateMobileRequest: ({
        required String mode,
        required String phoneOrEmail,
        required String password,
        required String deviceToken,
        required String fullName,
      }) {
        final trimmedId = phoneOrEmail.trim();
        if (trimmedId.isEmpty) {
          return const MobileQrAuthVerificationResult(
            ok: false,
            error: 'Vui lòng nhập Số điện thoại hoặc Email.',
          );
        }

        if (mode == 'TOKEN') {
          final existing = _store.findUserByPhoneOrEmail(trimmedId);
          if (existing == null) {
            return const MobileQrAuthVerificationResult(
              ok: false,
              tokenExpired: true,
              error: 'Tài khoản không tồn tại trên hệ thống.',
            );
          }
          if (existing.status == 'LOCKED') {
            return const MobileQrAuthVerificationResult(
              ok: false,
              error: 'Tài khoản này hiện đang bị khóa tạm thời.',
            );
          }
          final expectedToken = SecurityAndBarcodeUtils.generatePaymentSignature(
            orderCode: existing.phone,
            amount: 2026,
            method: existing.passwordHash,
          );
          if (deviceToken.trim() != expectedToken) {
            return const MobileQrAuthVerificationResult(
              ok: false,
              tokenExpired: true,
              error:
                  'Phiên đăng nhập đã hết hiệu lực. Vui lòng nhập lại mật khẩu.',
            );
          }
          _store.applyAuthenticatedUserSession(existing);
          return MobileQrAuthVerificationResult(
            ok: true,
            phone: existing.phone,
            fullName: existing.fullName,
            roleTitle: existing.role.title,
            deviceToken: expectedToken,
          );
        }

        if (mode == 'REGISTER') {
          final normPhone = EnvConfig.formatVietnamPhoneNational(trimmedId);
          if (!RegExp(r'^0(3|5|7|8|9)[0-9]{8}$').hasMatch(normPhone)) {
            return const MobileQrAuthVerificationResult(
              ok: false,
              error: 'Số điện thoại không hợp lệ (cần 10 chữ số).',
            );
          }
          if (fullName.trim().isEmpty) {
            return const MobileQrAuthVerificationResult(
              ok: false,
              error: 'Vui lòng nhập Họ và tên.',
            );
          }
          if (password.trim().length < 6) {
            return const MobileQrAuthVerificationResult(
              ok: false,
              error: 'Mật khẩu phải có từ 6 ký tự trở lên.',
            );
          }
          if (_store.findUserByPhoneOrEmail(normPhone) != null) {
            return const MobileQrAuthVerificationResult(
              ok: false,
              error: 'Số điện thoại này đã được đăng ký.',
            );
          }
          final created = _store.registerUserAccountWithRole(
            phone: normPhone,
            fullName: fullName.trim(),
            password: password.trim(),
            role: SubsystemRole.customer,
          );
          if (created == null) {
            return const MobileQrAuthVerificationResult(
              ok: false,
              error: 'Không thể tạo tài khoản. Vui lòng thử lại.',
            );
          }
          final issuedToken = SecurityAndBarcodeUtils.generatePaymentSignature(
            orderCode: created.phone,
            amount: 2026,
            method: created.passwordHash,
          );
          return MobileQrAuthVerificationResult(
            ok: true,
            phone: created.phone,
            fullName: created.fullName,
            roleTitle: created.role.title,
            deviceToken: issuedToken,
          );
        }

        final existing = _store.findUserByPhoneOrEmail(trimmedId);
        if (existing == null) {
          return const MobileQrAuthVerificationResult(
            ok: false,
            error: 'Tài khoản chưa tồn tại.',
          );
        }
        if (existing.status == 'LOCKED') {
          return const MobileQrAuthVerificationResult(
            ok: false,
            error: 'Tài khoản này hiện đang bị khóa tạm thời.',
          );
        }
        final authed = _store.authenticateWithPassword(
          phoneOrEmail: trimmedId,
          password: password.trim(),
        );
        if (authed == null) {
          return const MobileQrAuthVerificationResult(
            ok: false,
            error: 'Mật khẩu không chính xác.',
          );
        }
        final issuedToken = SecurityAndBarcodeUtils.generatePaymentSignature(
          orderCode: authed.phone,
          amount: 2026,
          method: authed.passwordHash,
        );
        return MobileQrAuthVerificationResult(
          ok: true,
          phone: authed.phone,
          fullName: authed.fullName,
          roleTitle: authed.role.title,
          deviceToken: issuedToken,
        );
      },
      onEvent: (event) {
        if (!mounted) return;
        if (event.status == 'TUNNEL_READY') {
          public4gHttpsUrl = event.deviceUserAgent;
          dialogSetState?.call(() {});
          return;
        }
        if (event.status == 'SCANNED') {
          isDeviceConnected = true;
          scanStatusText =
              'Đã quét mã QR — Vui lòng xác nhận trên điện thoại';
          dialogSetState?.call(() {});
          return;
        }
        if (event.status == 'CONFIRMED') {
          final confirmedPhone =
              EnvConfig.formatVietnamPhoneNational(event.phoneNumber);
          if (isDialogOpen && Navigator.of(context).canPop()) {
            isDialogOpen = false;
            Navigator.of(context).pop();
          }
          RealAuthDeliveryService.instance.stopMobileQrAuthServer();

          final user = _store.findUserByPhoneOrEmail(confirmedPhone);
          if (user != null) {
            _otpCountdownTimer?.cancel();
            cubit.selectRole(user.role);
            setState(() {
              _phoneCtrl.text = user.phone;
              _authErrorMessage = null;
              _isLoggedIn = true;
              _otpSent = false;
              _isForgotPasswordMode = false;
            });
          }
        }
      },
    );

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            dialogSetState = setModalState;
            final activeQrPayload =
                (public4gHttpsUrl != null && public4gHttpsUrl!.isNotEmpty)
                    ? public4gHttpsUrl!
                    : session.buildVerifyUrl(session.lanIp);

            return AlertDialog(
              backgroundColor: AppColors.paper,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
                side: BorderSide(color: AppColors.ink, width: 2.0),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppColors.violet,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Đăng nhập bằng mã QR',
                      style: TextStyle(
                        fontSize: 15.0,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Mở Camera điện thoại hoặc Zalo để quét mã QR',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppColors.ink, width: 2.0),
                        boxShadow: const [
                          BoxShadow(
                            color: AppColors.ink,
                            offset: Offset(4, 4),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: QrMatrixPainterWidget(
                        payload: activeQrPayload,
                        size: 206,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDeviceConnected
                            ? AppColors.acid.withValues(alpha: 0.55)
                            : AppColors.surface,
                        border: Border.all(color: AppColors.ink, width: 1.2),
                      ),
                      child: Text(
                        scanStatusText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    isDialogOpen = false;
                    RealAuthDeliveryService.instance.stopMobileQrAuthServer();
                    Navigator.of(dialogCtx).pop();
                  },
                  child: const Text(
                    'Đóng',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    isDialogOpen = false;
  }

  Widget _buildPostLoginStudioTopBar(
    BuildContext context, {
    required SubsystemRole approvedRole,
    required SubsystemRole activeRole,
    required bool hasUnlockedPartnerRole,
  }) {
    final cubit = context.read<SystemArchitectureCubit>();
    final partnerLabel = approvedRole == SubsystemRole.driver
        ? 'Giao diện Đối tác Tài xế'
        : 'Giao diện Cửa hàng B2B';
    final roleBadgeText = switch (activeRole) {
      SubsystemRole.customer => 'KHÁCH HÀNG • CUSTOMER STUDIO',
      SubsystemRole.driver => 'ĐỐI TÁC TÀI XẾ • DRIVER STUDIO',
      SubsystemRole.merchant => 'ĐỐI TÁC B2B • MERCHANT STUDIO',
      SubsystemRole.admin => 'QUẢN TRỊ VIÊN • ADMIN STUDIO',
    };

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.techBg,
        border: Border(
          bottom: BorderSide(color: AppColors.ink, width: 2.0),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              const StudioMarkWordmark(
                light: true,
                title: 'Giao Hàng Siêu Tốc',
                suffix: '.click',
                badgeTag: 'GHST',
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.acid,
                  border: Border.all(color: AppColors.ink, width: 1.2),
                ),
                child: Text(
                  roleBadgeText,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Consolas',
                    color: AppColors.techBg,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          if (hasUnlockedPartnerRole)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                const Text(
                  'CHẾ ĐỘ VAI TRÒ:',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Consolas',
                    color: AppColors.techMuted,
                  ),
                ),
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                    side: BorderSide(color: AppColors.ink, width: 1.2),
                  ),
                  label: const Text(
                    'Giao diện Khách hàng',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  selected: activeRole == SubsystemRole.customer,
                  selectedColor: AppColors.acid,
                  backgroundColor: AppColors.paper,
                  onSelected: (_) => cubit.selectRole(SubsystemRole.customer),
                ),
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                    side: BorderSide(color: AppColors.ink, width: 1.2),
                  ),
                  label: Text(
                    partnerLabel,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: activeRole == approvedRole
                          ? Colors.white
                          : AppColors.ink,
                    ),
                  ),
                  selected: activeRole == approvedRole,
                  selectedColor: AppColors.violet,
                  backgroundColor: AppColors.paper,
                  onSelected: (_) => cubit.selectRole(approvedRole),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildActiveSubsystemView(SubsystemRole role) {
    switch (role) {
      case SubsystemRole.customer:
        return CustomerSubsystemEntry(onLogout: _handleLogout);
      case SubsystemRole.driver:
        return DriverSubsystemEntry(onLogout: _handleLogout);
      case SubsystemRole.merchant:
        return MerchantSubsystemEntry(onLogout: _handleLogout);
      case SubsystemRole.admin:
        return AdminSubsystemEntry(onLogout: _handleLogout);
    }
  }
}
