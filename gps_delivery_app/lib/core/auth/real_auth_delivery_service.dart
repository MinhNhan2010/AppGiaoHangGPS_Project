import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../domain/enums/user_role.dart';
import '../config/env_config.dart';

class OtpDeliveryReceipt {
  final bool success;
  final bool deliveredExternally;
  final String channel;
  final String destination;
  final String message;

  const OtpDeliveryReceipt({
    required this.success,
    required this.deliveredExternally,
    required this.channel,
    required this.destination,
    required this.message,
  });
}

class GoogleOAuthResult {
  final String email;
  final String fullName;
  final String? phone;
  final SubsystemRole role;
  final String providerSub;

  const GoogleOAuthResult({
    required this.email,
    required this.fullName,
    this.phone,
    this.role = SubsystemRole.customer,
    required this.providerSub,
  });
}

class RealAuthDeliveryService {
  RealAuthDeliveryService._();
  static final RealAuthDeliveryService instance = RealAuthDeliveryService._();

  HttpServer? _activeOAuthServer;

  /// Thực thi gửi mã OTP 6 chữ số qua giao thức SMTP TLS thật (Email) hoặc HTTP SMS Webhook thật
  Future<OtpDeliveryReceipt> deliverOtpChallenge({
    required String destination,
    required String otpCode,
  }) async {
    final target = destination.trim();
    final isEmail = target.contains('@');

    if (isEmail) {
      if (!EnvConfig.isSmtpConfigured) {
        return OtpDeliveryReceipt(
          success: false,
          deliveredExternally: false,
          channel: 'SMTP_NOT_CONFIGURED',
          destination: target,
          message:
              'Chưa cấu hình tài khoản SMTP TLS trong EnvConfig để gửi Email OTP.',
        );
      }
      return _sendRealSmtpTlsEmail(
        recipientEmail: target,
        otpCode: otpCode,
      );
    } else {
      if (!EnvConfig.isSmsWebhookConfigured) {
        return OtpDeliveryReceipt(
          success: false,
          deliveredExternally: false,
          channel: 'SMS_NOT_CONFIGURED',
          destination: target,
          message:
              'Chưa cấu hình cổng SMS Gateway (SMS_WEBHOOK_URL). Vui lòng nhập địa chỉ Email để nhận mã OTP thật qua SMTP.',
        );
      }
      return _sendRealSmsWebhook(
        phoneNumber: target,
        otpCode: otpCode,
      );
    }
  }

  /// Giao thức RFC-5321 SMTP over TLS (Cổng 465 / 587) gửi Email OTP thật tới hộp thư người nhận
  Future<OtpDeliveryReceipt> _sendRealSmtpTlsEmail({
    required String recipientEmail,
    required String otpCode,
  }) async {
    Socket? rawSocket;
    SecureSocket? tlsSocket;
    StreamSubscription<String>? sub;
    try {
      final host = EnvConfig.smtpHost;
      final port = EnvConfig.smtpPort;
      final sender = EnvConfig.smtpSenderEmail.trim();
      final password = EnvConfig.smtpAppPassword.replaceAll(' ', '').trim();

      final responseQueue = <String>[];
      Completer<String>? lineCompleter;

      void onDataLine(String chunk) {
        for (final rawLine in chunk.split('\r\n')) {
          final line = rawLine.trim();
          if (line.isEmpty) continue;
          responseQueue.add(line);
          if (line.length >= 3 &&
              int.tryParse(line.substring(0, 3)) != null &&
              (line.length == 3 || line[3] == ' ')) {
            if (lineCompleter != null && !lineCompleter!.isCompleted) {
              lineCompleter!.complete(line);
            }
          }
        }
      }

      Future<String> waitServerCode() async {
        if (responseQueue.isNotEmpty) {
          final last = responseQueue.last;
          if (last.length >= 3 &&
              int.tryParse(last.substring(0, 3)) != null &&
              (last.length == 3 || last[3] == ' ')) {
            responseQueue.clear();
            return last;
          }
        }
        lineCompleter = Completer<String>();
        final res = await lineCompleter!.future.timeout(
          const Duration(seconds: 8),
        );
        responseQueue.clear();
        return res;
      }

      if (port == 465) {
        tlsSocket = await SecureSocket.connect(
          host,
          port,
          timeout: const Duration(seconds: 8),
        );
        sub = utf8.decoder.bind(tlsSocket).listen(onDataLine);
        await waitServerCode();
      } else {
        rawSocket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 8),
        );
        sub = utf8.decoder.bind(rawSocket).listen(onDataLine);
        await waitServerCode();
        rawSocket.write('EHLO ghst.vn\r\n');
        await waitServerCode();
        rawSocket.write('STARTTLS\r\n');
        final tlsReady = await waitServerCode();
        if (!tlsReady.startsWith('220')) {
          throw SocketException('Máy chủ SMTP không hỗ trợ STARTTLS: $tlsReady');
        }
        await sub.cancel();
        tlsSocket = await SecureSocket.secure(rawSocket);
        sub = utf8.decoder.bind(tlsSocket).listen(onDataLine);
      }

      void sendCmd(String cmd) {
        tlsSocket!.write('$cmd\r\n');
      }

      sendCmd('EHLO ghst.vn');
      await waitServerCode();

      sendCmd('AUTH LOGIN');
      final authPrompt1 = await waitServerCode();
      if (!authPrompt1.startsWith('334')) {
        throw SocketException('SMTP AUTH LOGIN thất bại: $authPrompt1');
      }

      sendCmd(base64Encode(utf8.encode(sender)));
      final authPrompt2 = await waitServerCode();
      if (!authPrompt2.startsWith('334')) {
        throw SocketException('SMTP từ chối tài khoản gửi: $authPrompt2');
      }

      sendCmd(base64Encode(utf8.encode(password)));
      final authResult = await waitServerCode();
      if (!authResult.startsWith('235')) {
        throw SocketException(
          'Xác thực mật khẩu ứng dụng SMTP thất bại: $authResult',
        );
      }

      sendCmd('MAIL FROM:<$sender>');
      final mailFromRes = await waitServerCode();
      if (!mailFromRes.startsWith('250')) {
        throw SocketException('MAIL FROM lỗi: $mailFromRes');
      }

      sendCmd('RCPT TO:<$recipientEmail>');
      final rcptRes = await waitServerCode();
      if (!rcptRes.startsWith('250')) {
        throw SocketException('RCPT TO lỗi: $rcptRes');
      }

      sendCmd('DATA');
      final dataPrompt = await waitServerCode();
      if (!dataPrompt.startsWith('354')) {
        throw SocketException('SMTP DATA lỗi: $dataPrompt');
      }

      final subjectB64 = base64Encode(
        utf8.encode('[GHST] Mã xác thực OTP của bạn là $otpCode'),
      );
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      final emailPayload = StringBuffer()
        ..writeln('From: "Giao Hang Sieu Toc (GHST)" <$sender>')
        ..writeln('To: <$recipientEmail>')
        ..writeln('Subject: =?UTF-8?B?$subjectB64?=')
        ..writeln('MIME-Version: 1.0')
        ..writeln('Content-Type: text/html; charset=UTF-8')
        ..writeln()
        ..writeln(
          '<div style="font-family:Segoe UI,Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;background:#F5F1E8;border:2px solid #15131E;">'
          '<div style="background:#CBFF3E;display:inline-block;padding:4px 10px;border:1px solid #15131E;font-weight:900;font-size:12px;">GHST • GIAO HÀNG SIÊU TỐC</div>'
          '<h2 style="color:#15131E;margin:14px 0 8px;">Mã xác thực OTP đăng nhập</h2>'
          '<p style="color:#333;font-size:14px;">Xin chào, mã xác thực OTP 6 chữ số của bạn là:</p>'
          '<div style="background:#15131E;color:#CBFF3E;font-size:32px;font-weight:900;letter-spacing:8px;text-align:center;padding:16px;margin:16px 0;">$otpCode</div>'
          '<p style="color:#555;font-size:12px;">Mã có hiệu lực trong vòng 120 giây (Thời điểm cấp: $nowUtc).</p>'
          '</div>',
        )
        ..writeln('.');

      tlsSocket.write(
        emailPayload.toString().replaceAll('\r\n', '\n').replaceAll('\n', '\r\n'),
      );
      final sendRes = await waitServerCode();
      sendCmd('QUIT');

      if (!sendRes.startsWith('250')) {
        throw SocketException('Gửi nội dung thư thất bại: $sendRes');
      }

      return OtpDeliveryReceipt(
        success: true,
        deliveredExternally: true,
        channel: 'SMTP_TLS',
        destination: recipientEmail,
        message:
            'Đã gửi mã OTP 6 chữ số tới hộp thư $recipientEmail. Vui lòng kiểm tra Email và nhập mã bên dưới.',
      );
    } catch (e) {
      return OtpDeliveryReceipt(
        success: false,
        deliveredExternally: false,
        channel: 'SMTP_TLS_ERROR',
        destination: recipientEmail,
        message: 'Lỗi kết nối SMTP: $e',
      );
    } finally {
      await sub?.cancel();
      await tlsSocket?.close();
      await rawSocket?.close();
    }
  }

  /// Gửi SMS OTP qua HTTP Webhook Gateway thực tế
  Future<OtpDeliveryReceipt> _sendRealSmsWebhook({
    required String phoneNumber,
    required String otpCode,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final uri = Uri.parse(EnvConfig.smsWebhookUrl);
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      final body = jsonEncode({
        'phone': phoneNumber,
        'otp': otpCode,
        'message':
            '[GHST] Ma xac thuc OTP Giao Hang Sieu Toc cua ban la: $otpCode (Hieu luc 120s)',
      });
      req.add(utf8.encode(body));
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return OtpDeliveryReceipt(
          success: true,
          deliveredExternally: true,
          channel: 'SMS_WEBHOOK',
          destination: phoneNumber,
          message:
              'Đã gửi SMS OTP thật tới số $phoneNumber qua cổng SMS Gateway!',
        );
      }
      return OtpDeliveryReceipt(
        success: false,
        deliveredExternally: false,
        channel: 'SMS_WEBHOOK_ERROR',
        destination: phoneNumber,
        message: 'SMS Gateway trả về mã HTTP ${res.statusCode}',
      );
    } catch (e) {
      return OtpDeliveryReceipt(
        success: false,
        deliveredExternally: false,
        channel: 'SMS_WEBHOOK_ERROR',
        destination: phoneNumber,
        message: 'Lỗi kết nối SMS Webhook: $e',
      );
    } finally {
      client.close(force: true);
    }
  }

  bool _isExchangingOAuthCode = false;
  void Function(GoogleOAuthResult result)? _activeOnAuthenticated;
  static const String defaultRedirectUri =
      'http://127.0.0.1:8765/oauth2callback';

  /// Xử lý URL callback chứa `code` từ WebView nhúng hoặc máy chủ Loopback cục bộ
  Future<GoogleOAuthResult?> tryProcessOAuthCallbackUrl(String rawUrl) async {
    if (_isExchangingOAuthCode) return null;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.path != '/oauth2callback') return null;
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) return null;

    _isExchangingOAuthCode = true;
    final authResult = await exchangeGoogleAuthCodeForUserProfile(
      code: code,
      redirectUri: defaultRedirectUri,
    );
    if (authResult != null) {
      final cb = _activeOnAuthenticated;
      _activeOnAuthenticated = null;
      cb?.call(authResult);
      await stopGoogleOAuthServer();
    } else {
      _isExchangingOAuthCode = false;
    }
    return authResult;
  }

  /// Khởi chạy máy chủ HTTP Loopback cục bộ (`127.0.0.1:8765`) và trả về URL `accounts.google.com` để nhúng trực tiếp vào WebView trong ứng dụng
  Future<String?> startGoogleOAuth2LoopbackFlow({
    required void Function(GoogleOAuthResult result) onAuthenticated,
    bool openSystemBrowser = false,
  }) async {
    if (!EnvConfig.isGoogleOAuthConfigured) {
      return null;
    }
    await stopGoogleOAuthServer();
    _isExchangingOAuthCode = false;
    _activeOnAuthenticated = onAuthenticated;

    final googleAuthUrl = Uri.https(
      'accounts.google.com',
      '/o/oauth2/v2/auth',
      {
        'client_id': EnvConfig.googleClientId,
        'redirect_uri': defaultRedirectUri,
        'response_type': 'code',
        'scope': 'openid email profile',
        'prompt': 'select_account',
      },
    ).toString();

    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        8765,
        shared: true,
      );
      _activeOAuthServer = server;

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/oauth2callback') {
          final fullCallbackUrl =
              'http://127.0.0.1:8765${request.uri.toString()}';
          final authResult = await tryProcessOAuthCallbackUrl(fullCallbackUrl);

          request.response.headers.contentType =
              ContentType('text', 'html', charset: 'utf-8');
          if (authResult != null) {
            request.response.write(_buildOAuthSuccessHtml(authResult));
          } else {
            request.response.write(
              '<html><body style="font-family:sans-serif;padding:40px;">'
              '<h3>Đang đồng bộ phiên đăng nhập Google vào ứng dụng...</h3>'
              '</body></html>',
            );
          }
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
    } catch (_) {
      // Nếu cổng 8765 không mở được trên thiết bị di động, WebView vẫn bắt trực tiếp URL redirect thông qua tryProcessOAuthCallbackUrl
    }

    if (openSystemBrowser) {
      await launchUrlInSystemBrowser(googleAuthUrl);
    }
    return googleAuthUrl;
  }

  Future<GoogleOAuthResult?> exchangeGoogleAuthCodeForUserProfile({
    required String code,
    required String redirectUri,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final tokenReq = await client.postUrl(
        Uri.parse('https://oauth2.googleapis.com/token'),
      );
      tokenReq.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded',
      );
      final formBody = Uri(
        queryParameters: {
          'code': code,
          'client_id': EnvConfig.googleClientId,
          'client_secret': EnvConfig.googleClientSecret,
          'redirect_uri': redirectUri,
          'grant_type': 'authorization_code',
        },
      ).query;
      tokenReq.add(utf8.encode(formBody));
      final tokenRes = await tokenReq.close();
      final tokenJsonStr = await utf8.decoder.bind(tokenRes).join();
      final tokenMap = jsonDecode(tokenJsonStr) as Map<String, dynamic>;
      final accessToken = tokenMap['access_token']?.toString();
      if (accessToken == null || accessToken.isEmpty) return null;

      final infoReq = await client.getUrl(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
      );
      infoReq.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
      final infoRes = await infoReq.close();
      final infoJsonStr = await utf8.decoder.bind(infoRes).join();
      final infoMap = jsonDecode(infoJsonStr) as Map<String, dynamic>;

      final email = infoMap['email']?.toString() ?? '';
      final name = infoMap['name']?.toString() ?? email.split('@').first;
      final sub = infoMap['sub']?.toString() ?? 'google-$email';
      if (!email.contains('@')) return null;

      return GoogleOAuthResult(
        email: email,
        fullName: name,
        providerSub: sub,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> stopGoogleOAuthServer() async {
    final srv = _activeOAuthServer;
    _activeOAuthServer = null;
    if (srv != null) {
      try {
        await srv.close(force: true);
      } catch (_) {}
    }
  }

  Future<void> launchUrlInSystemBrowser(String url) async {
    try {
      if (Platform.isWindows) {
        final escaped = url.replaceAll("'", "''");
        await Process.run(
          'powershell',
          ['-NoProfile', '-Command', "Start-Process '$escaped'"],
        );
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }

  String _buildOAuthSuccessHtml(GoogleOAuthResult res) {
    return '''<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="UTF-8">
<title>Đã xác thực Google — GHST</title>
</head>
<body style="margin:0;background:#080B0F;color:#15131E;font-family:Segoe UI,Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;">
  <div style="background:#F5F1E8;border:2px solid #15131E;box-shadow:12px 12px 0 #CBFF3E;max-width:440px;width:100%;padding:28px;text-align:center;">
    <div style="background:#CBFF3E;border:1px solid #15131E;display:inline-block;padding:4px 12px;font-weight:900;font-size:12px;">
      XÁC THỰC GOOGLE THÀNH CÔNG
    </div>
    <h2 style="margin:14px 0 8px;">Xin chào, ${res.fullName}!</h2>
    <p style="font-size:14px;color:#333;">Tài khoản <strong>${res.email}</strong> đã được đồng bộ vào ứng dụng <strong>Giao Hàng Siêu Tốc (GHST)</strong>.</p>
    <p style="font-size:12.5px;color:#555;margin-top:16px;">Bạn có thể đóng tab trình duyệt này và quay lại cửa sổ ứng dụng.</p>
  </div>
</body>
</html>''';
  }
}
