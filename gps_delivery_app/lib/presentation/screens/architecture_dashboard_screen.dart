import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/auth/real_auth_delivery_service.dart';
import '../../core/config/env_config.dart';
import '../../core/theme/app_colors.dart';
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
  final TextEditingController _otpCtrl = TextEditingController();

  late final AnimationController _login3dController;
  double _loginParallaxX = 0.0;
  double _loginParallaxY = 0.0;

  bool _showStartup3dSplash = false;
  bool _isLoggedIn = false;
  bool _otpSent = false;
  bool _isDeliveringOtp = false;
  OtpDeliveryReceipt? _lastOtpReceipt;
  bool _isRegisterMode = false;
  bool _usePasswordLogin = false;
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

  @override
  void dispose() {
    RealAuthDeliveryService.instance.stopGoogleOAuthServer();
    _login3dController.dispose();
    _store.removeListener(_onStoreUpdated);
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _fullNameCtrl.dispose();
    _passwordCtrl.dispose();
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
          _authErrorMessage = 'Vui lòng nhập số điện thoại hợp lệ (từ 9 chữ số).';
        });
        return;
      }
      final rawEmail = _emailCtrl.text.trim();
      if (rawEmail.isEmpty || !rawEmail.contains('@') || !rawEmail.contains('.')) {
        setState(() {
          _authErrorMessage =
              'Vui lòng nhập địa chỉ Email hợp lệ để nhận mã xác thực OTP.';
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
          _store.findUserByPhoneOrEmail(rawEmail);
      if (existingUser != null) {
        setState(() {
          _authErrorMessage =
              'Số điện thoại hoặc Email này đã được đăng ký. Vui lòng chuyển sang tab "Đăng nhập".';
        });
        return;
      }
    }

    final otp = _store.generateOtpForPhone(rawInput);
    final registerEmail = _emailCtrl.text.trim();
    final existingAccount = _store.findUserByPhoneOrEmail(rawInput);
    final String deliveryDestination;
    if (_isRegisterMode && registerEmail.contains('@')) {
      deliveryDestination = registerEmail;
    } else if (!rawInput.contains('@') &&
        !EnvConfig.isSmsWebhookConfigured &&
        existingAccount != null &&
        existingAccount.email.contains('@')) {
      deliveryDestination = existingAccount.email;
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

  void _handleVerifyOtpAndAuthenticate(BuildContext context) {
    final rawInput = _phoneCtrl.text.trim();
    final inputOtp = _otpCtrl.text.trim();

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

    context.read<SystemArchitectureCubit>().selectRole(user.role);
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
            _isRegisterMode ? 'Tạo tài khoản mới' : 'Đăng nhập hệ thống',
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
                ? 'Điền thông tin cá nhân để bắt đầu đặt đơn giao hàng'
                : (_usePasswordLogin
                    ? 'Nhập Số điện thoại / Email và mật khẩu đã đăng ký'
                    : 'Nhập Số điện thoại hoặc Email để nhận mã xác thực OTP'),
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
                      ),
                    ),
                    selected: !_usePasswordLogin,
                    selectedColor: AppColors.acid,
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                    onSelected: (_) => setState(() {
                      _usePasswordLogin = false;
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
                      ),
                    ),
                    selected: _usePasswordLogin,
                    selectedColor: AppColors.acid,
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                    onSelected: (_) => setState(() {
                      _usePasswordLogin = true;
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
                hintText: 'Ví dụ: ban@gmail.com',
                labelText: 'Địa chỉ Email (nhận mã OTP)',
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
          if (_otpSent && !_usePasswordLogin) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.acid.withValues(alpha: 0.35),
                border: Border.all(color: AppColors.ink, width: 1.0),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.mark_email_read_outlined,
                    size: 15,
                    color: AppColors.ink,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isDeliveringOtp
                          ? 'Đang gửi mã xác thực OTP...'
                          : (_lastOtpReceipt?.message ??
                              'Mã xác thực OTP đã được gửi đi.'),
                      style: const TextStyle(
                        fontSize: 11.2,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _handleSendOtp,
                    child: const Text(
                      'Gửi lại',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.violet,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
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
                if (!_isRegisterMode && _usePasswordLogin) {
                  _handlePasswordLogin(context);
                } else if (!_otpSent) {
                  _handleSendOtp();
                } else {
                  _handleVerifyOtpAndAuthenticate(context);
                }
              },
              child: Text(
                (!_isRegisterMode && _usePasswordLogin)
                    ? 'Đăng nhập'
                    : (_otpSent
                        ? (_isRegisterMode
                            ? 'Xác nhận OTP & Tạo tài khoản'
                            : 'Xác nhận OTP & Đăng nhập')
                        : 'Gửi mã OTP'),
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
                  label: const Text('Giao diện Khách hàng'),
                  selected: activeRole == SubsystemRole.customer,
                  selectedColor: AppColors.acid,
                  backgroundColor: AppColors.paper,
                  labelStyle: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                  onSelected: (_) => cubit.selectRole(SubsystemRole.customer),
                ),
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                    side: BorderSide(color: AppColors.ink, width: 1.2),
                  ),
                  label: Text(partnerLabel),
                  selected: activeRole == approvedRole,
                  selectedColor: AppColors.violet,
                  backgroundColor: AppColors.paper,
                  labelStyle: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: activeRole == approvedRole
                        ? Colors.white
                        : AppColors.ink,
                  ),
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
