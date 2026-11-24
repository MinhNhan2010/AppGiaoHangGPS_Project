import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/integrations/bank_directory_service.dart';
import '../../core/integrations/cloud_account_session.dart';
import '../../core/integrations/cloud_session_lease.dart';
import '../../core/network/public_json_api.dart';
import '../../core/theme/ghst_theme_tokens.dart';
import '../../core/utils/currency_formatter.dart';
import 'animated_3d_ui_icons.dart';
import 'cloud_session_boundary.dart';
import 'ghst_button_icon.dart';
import 'vietqr_bank_payment_panel.dart';

String _vnd(dynamic value) =>
    CurrencyFormatter.formatVnd((value as num? ?? 0).toDouble());

String _shortTime(dynamic raw) {
  final text = '${raw ?? ''}'.trim();
  if (text.isEmpty) return '';
  final parsed = DateTime.tryParse(text)?.toLocal();
  if (parsed == null) return text;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(parsed.day)}/${two(parsed.month)} ${two(parsed.hour)}:${two(parsed.minute)}';
}

Future<void> openDriverCloudWallet(
  BuildContext context,
  CloudAccountSession session,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CloudSessionBoundary(
      session: session,
      roles: const {'driver'},
      builder: (_, lease) => Scaffold(
        appBar: AppBar(title: const Text('Ví Tài xế & Đối soát 80/20')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: DriverCloudWalletPanel(
                  session: session,
                  lease: lease,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

class DriverCloudWalletPanel extends StatefulWidget {
  const DriverCloudWalletPanel({
    super.key,
    required this.session,
    required this.lease,
    this.compact = false,
  });

  final CloudAccountSession session;
  final CloudSessionLease lease;
  final bool compact;

  @override
  State<DriverCloudWalletPanel> createState() => _DriverCloudWalletPanelState();
}

class _DriverCloudWalletPanelState extends State<DriverCloudWalletPanel> {
  Map<String, dynamic>? _summary;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;
  bool _requestsTab = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool silent = false}) async {
    if (!widget.lease.valid) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await widget.session.service.driverWallet('summary');
      if (!mounted || !widget.lease.valid) return;
      setState(() {
        _summary = res;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || widget.lease.handleAccessFailure(e)) return;
      setState(() {
        _loading = false;
        _error = e is PublicApiException
            ? e.message
            : 'Chưa tải được dữ liệu Ví Tài xế.';
      });
    }
  }

  Map<String, dynamic> get _wallet => _summary?['wallet'] is Map
      ? Map<String, dynamic>.from(_summary!['wallet'] as Map)
      : const {};

  List<Map<String, dynamic>> get _requests =>
      (_summary?['requests'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  List<Map<String, dynamic>> get _ledger =>
      (_summary?['ledger'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  Future<void> _showQrForTopup(Map<String, dynamic> request) async {
    final amount = (request['amount'] as num? ?? 0).toDouble();
    final transferCode = '${request['transfer_code'] ?? ''}'.trim();
    if (amount <= 0 || transferCode.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => CloudSessionBoundary(
        session: widget.session,
        roles: const {'driver'},
        dialog: true,
        builder: (dialogCtx, _) => AlertDialog(
          title: const Text('Quét mã VietQR nạp ký quỹ'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VietQrBankPaymentPanel(
                    amountVnd: amount,
                    orderReference: transferCode,
                    reconciliationNote:
                        'Chuyển khoản đúng số tiền và nội dung "$transferCode". Quản trị viên xác nhận đối soát và cộng ngay vào số dư ví tài xế.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogCtx),
              icon: const GhstButtonIcon.glyph(GhstActionKind.check, size: 16),
              label: const Text('Đã lưu mã / Đóng'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTopupDialog() async {
    if (_busy || !widget.lease.valid) return;
    final amountCtrl = TextEditingController(text: '200000');
    final noteCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    Map<String, dynamic>? createdRequest;

    var submitting = false;
    String? localErr;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => CloudSessionBoundary(
          session: widget.session,
          roles: const {'driver'},
          dialog: true,
          builder: (dialogCtx, _) => StatefulBuilder(
            builder: (ctx, setDialogState) {
              return AlertDialog(
                title: const Text('Nạp ký quỹ qua VietQR (NAPAS 247)'),
                content: SizedBox(
                  width: 420,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Chọn nhanh mức ký quỹ đề xuất hoặc nhập số tiền từ 50.000đ đến 50.000.000đ:',
                            style: TextStyle(fontSize: 12.5),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final preset in [
                                100000,
                                200000,
                                500000,
                                1000000,
                              ])
                                ActionChip(
                                  avatar: const GhstButtonIcon.glyph(
                                    GhstActionKind.qr,
                                    size: 14,
                                  ),
                                  label: Text(_vnd(preset)),
                                  onPressed: submitting
                                      ? null
                                      : () => setDialogState(
                                          () => amountCtrl.text = '$preset',
                                        ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const ValueKey('driver-wallet-topup-amount'),
                            controller: amountCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Số tiền nạp (VNĐ)',
                              suffixText: 'đ',
                            ),
                            validator: (v) {
                              final parsed = int.tryParse((v ?? '').trim());
                              if (parsed == null ||
                                  parsed < 50000 ||
                                  parsed > 50000000) {
                                return 'Nhập từ 50.000 đến 50.000.000 đ.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: noteCtrl,
                            maxLength: 200,
                            decoration: const InputDecoration(
                              labelText: 'Ghi chú (tùy chọn)',
                            ),
                          ),
                          if (localErr != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              localErr!,
                              style: TextStyle(
                                color: Theme.of(ctx).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton.icon(
                    onPressed: submitting
                        ? null
                        : () => Navigator.pop(dialogCtx),
                    icon: const GhstButtonIcon.glyph(
                      GhstActionKind.close,
                      size: 16,
                    ),
                    label: const Text('Hủy'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('driver-wallet-topup-submit'),
                    onPressed: submitting
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setDialogState(() {
                              submitting = true;
                              localErr = null;
                            });
                            try {
                              final res = await widget.session.service
                                  .driverWallet('request_topup', {
                                    'amount': int.parse(amountCtrl.text.trim()),
                                    'driver_note': noteCtrl.text.trim(),
                                    'request_key': const Uuid().v4(),
                                  });
                              if (res['request'] is Map) {
                                createdRequest = Map<String, dynamic>.from(
                                  res['request'] as Map,
                                );
                              }
                              if (dialogCtx.mounted) {
                                Navigator.pop(dialogCtx);
                              }
                            } catch (e) {
                              if (!widget.lease.handleAccessFailure(e) &&
                                  ctx.mounted) {
                                setDialogState(() {
                                  submitting = false;
                                  localErr = e is PublicApiException
                                      ? e.message
                                      : 'Chưa tạo được lệnh nạp ký quỹ.';
                                });
                              }
                            }
                          },
                    icon: const GhstButtonIcon.glyph(
                      GhstActionKind.qr,
                      size: 16,
                    ),
                    label: const Text('Tạo mã VietQR'),
                  ),
                ],
              );
            },
          ),
        ),
      );
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        amountCtrl.dispose();
        noteCtrl.dispose();
      });
    }

    if (createdRequest != null && mounted && widget.lease.valid) {
      setState(() {
        _requestsTab = true;
        _notice =
            'Đã tạo lệnh nạp ${_vnd(createdRequest!['amount'])}. Quét mã VietQR bên dưới để chuyển khoản.';
      });
      await _load(silent: true);
      if (mounted) await _showQrForTopup(createdRequest!);
    }
  }

  Future<void> _openBankOrWithdrawDialog({required bool withdraw}) async {
    if (_busy || !widget.lease.valid) return;
    final banks = VietQrBankPaymentPanel.defaultVietnamBanks;
    var selectedBin = '${_wallet['bank_bin'] ?? ''}'.trim();
    if (!banks.any((b) => b.bin == selectedBin)) {
      selectedBin = banks.first.bin;
    }
    final accNoCtrl = TextEditingController(
      text: '${_wallet['bank_account_no'] ?? ''}',
    );
    final accNameCtrl = TextEditingController(
      text: '${_wallet['bank_account_name'] ?? ''}',
    );
    final amountCtrl = TextEditingController(text: '100000');
    final noteCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var completed = false;
    var submitting = false;
    String? localErr;

    try {
      await showDialog<void>(
        context: context,
        builder: (_) => CloudSessionBoundary(
          session: widget.session,
          roles: const {'driver'},
          dialog: true,
          builder: (dialogCtx, _) => StatefulBuilder(
            builder: (ctx, setDialogState) {
              DirectoryBank currentBank() => banks.firstWhere(
                (b) => b.bin == selectedBin,
                orElse: () => banks.first,
              );
              return AlertDialog(
                title: Text(
                  withdraw
                      ? 'Rút thu nhập về Ngân hàng'
                      : 'Tài khoản Ngân hàng nhận tiền',
                ),
                content: SizedBox(
                  width: 430,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (withdraw) ...[
                            Text(
                              'Số dư khả dụng: ${_vnd(_wallet['balance'])}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          DropdownButtonFormField<String>(
                            icon: const GhstButtonIcon.glyph(
                              GhstActionKind.down,
                              size: 18,
                            ),
                            initialValue: selectedBin,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Ngân hàng thụ hưởng',
                            ),
                            items: [
                              for (final b in banks)
                                DropdownMenuItem(
                                  value: b.bin,
                                  child: Text(
                                    '${b.shortName} (${b.code})',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: submitting
                                ? null
                                : (val) {
                                    if (val != null) {
                                      setDialogState(() => selectedBin = val);
                                    }
                                  },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            key: const ValueKey('driver-wallet-bank-no'),
                            controller: accNoCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Số tài khoản ngân hàng',
                            ),
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (!RegExp(r'^[0-9A-Za-z]{6,24}$').hasMatch(t)) {
                                return 'Nhập STK hợp lệ (6–24 ký tự số/chữ).';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            key: const ValueKey('driver-wallet-bank-owner'),
                            controller: accNameCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Tên chủ tài khoản (không dấu)',
                            ),
                            validator: (v) => (v ?? '').trim().length < 3
                                ? 'Nhập tên chủ tài khoản tối thiểu 3 ký tự.'
                                : null,
                          ),
                          if (withdraw) ...[
                            const SizedBox(height: 10),
                            TextFormField(
                              key: const ValueKey(
                                'driver-wallet-withdraw-amount',
                              ),
                              controller: amountCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Số tiền rút (VNĐ)',
                                suffixText: 'đ',
                              ),
                              validator: (v) {
                                final parsed = int.tryParse((v ?? '').trim());
                                if (parsed == null ||
                                    parsed < 50000 ||
                                    parsed > 50000000) {
                                  return 'Số tiền rút từ 50.000 đến 50.000.000 đ.';
                                }
                                final avail =
                                    (_wallet['balance'] as num? ?? 0).toInt();
                                if (parsed > avail) {
                                  return 'Vượt quá số dư khả dụng (${_vnd(avail)}).';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: noteCtrl,
                              maxLength: 200,
                              decoration: const InputDecoration(
                                labelText: 'Ghi chú rút tiền (tùy chọn)',
                              ),
                            ),
                          ],
                          if (localErr != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              localErr!,
                              style: TextStyle(
                                color: Theme.of(ctx).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton.icon(
                    onPressed: submitting
                        ? null
                        : () => Navigator.pop(dialogCtx),
                    icon: const GhstButtonIcon.glyph(
                      GhstActionKind.close,
                      size: 16,
                    ),
                    label: const Text('Hủy'),
                  ),
                  FilledButton.icon(
                    key: ValueKey(
                      withdraw
                          ? 'driver-wallet-withdraw-submit'
                          : 'driver-wallet-bank-save',
                    ),
                    onPressed: submitting
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setDialogState(() {
                              submitting = true;
                              localErr = null;
                            });
                            final bank = currentBank();
                            try {
                              if (withdraw) {
                                await widget.session.service.driverWallet(
                                  'request_withdraw',
                                  {
                                    'amount': int.parse(amountCtrl.text.trim()),
                                    'bank_bin': bank.bin,
                                    'bank_name': bank.shortName,
                                    'bank_account_no': accNoCtrl.text.trim(),
                                    'bank_account_name': accNameCtrl.text
                                        .trim()
                                        .toUpperCase(),
                                    'driver_note': noteCtrl.text.trim(),
                                    'request_key': const Uuid().v4(),
                                  },
                                );
                              } else {
                                await widget.session.service.driverWallet(
                                  'save_bank',
                                  {
                                    'bank_bin': bank.bin,
                                    'bank_name': bank.shortName,
                                    'bank_account_no': accNoCtrl.text.trim(),
                                    'bank_account_name': accNameCtrl.text
                                        .trim()
                                        .toUpperCase(),
                                  },
                                );
                              }
                              completed = true;
                              if (dialogCtx.mounted) {
                                Navigator.pop(dialogCtx);
                              }
                            } catch (e) {
                              if (!widget.lease.handleAccessFailure(e) &&
                                  ctx.mounted) {
                                setDialogState(() {
                                  submitting = false;
                                  localErr = e is PublicApiException
                                      ? e.message
                                      : 'Chưa lưu được yêu cầu.';
                                });
                              }
                            }
                          },
                    icon: GhstButtonIcon.glyph(
                      withdraw ? GhstActionKind.download : GhstActionKind.save,
                      size: 16,
                    ),
                    label: Text(withdraw ? 'Gửi lệnh rút' : 'Lưu ngân hàng'),
                  ),
                ],
              );
            },
          ),
        ),
      );
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        accNoCtrl.dispose();
        accNameCtrl.dispose();
        amountCtrl.dispose();
        noteCtrl.dispose();
      });
    }

    if (completed && mounted && widget.lease.valid) {
      setState(() {
        if (withdraw) _requestsTab = true;
        _notice = withdraw
            ? 'Đã gửi yêu cầu rút tiền và tạm khóa số dư chờ duyệt chuyển khoản.'
            : 'Đã lưu tài khoản ngân hàng nhận tiền.';
      });
      await _load(silent: true);
    }
  }

  Future<void> _cancelRequest(Map<String, dynamic> req) async {
    if (_busy || !widget.lease.valid) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.session.service.driverWallet('cancel_request', {
        'request_id': req['id'],
      });
      if (!mounted || !widget.lease.valid) return;
      setState(() => _notice = 'Đã hủy yêu cầu và hoàn mở khóa số dư (nếu có).');
      await _load(silent: true);
    } catch (e) {
      if (!mounted || widget.lease.handleAccessFailure(e)) return;
      setState(() {
        _error = e is PublicApiException
            ? e.message
            : 'Chưa hủy được yêu cầu.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _ledgerLabel(String kind) => switch (kind) {
    'trip_earning_80' => 'Cộng 80% cước chuyến giao',
    'trip_cash_fee_deduct' => 'Khấu trừ cước đã thu tiền mặt',
    'topup_approved' => 'Nạp ký quỹ VietQR thành công',
    'withdraw_lock' => 'Tạm khóa chờ rút ngân hàng',
    'withdraw_unlock_cancel' => 'Hoàn mở khóa (tự hủy lệnh rút)',
    'withdraw_unlock_reject' => 'Hoàn mở khóa (từ chối lệnh rút)',
    'withdraw_completed' => 'Đã giải ngân về ngân hàng',
    'operator_adjust' => 'Điều chỉnh đối soát vận hành',
    _ => kind,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final balance = (_wallet['balance'] as num? ?? 0).toInt();
    final locked = (_wallet['locked_balance'] as num? ?? 0).toInt();
    final earned = (_wallet['total_earned'] as num? ?? 0).toInt();
    final commission = (_wallet['total_commission'] as num? ?? 0).toInt();
    final escrowTarget = (_wallet['escrow_target'] as num? ?? 200000).toInt();
    final codHeld = (_wallet['cod_holding'] as num? ?? 0).toInt();
    final deliveredCount =
        (_wallet['trips_settled_count'] as num? ?? 0).toInt();
    final escrowRatio = escrowTarget <= 0
        ? 1.0
        : (balance / escrowTarget).clamp(0.0, 1.0);
    final pendingTopup = _requests
        .where((r) => r['kind'] == 'topup' && r['state'] == 'pending')
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GhstLuminousCard(
          accentGlow: balance >= 0 ? tokens.emerald.glow : tokens.amber.glow,
          borderColor:
              balance >= 0 ? tokens.emerald.border : tokens.amber.border,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GhstAiIcon(
                        style: Icon3dStyle.walletVault,
                        size: 40,
                        borderRadius: 12,
                        selected: true,
                        borderColor: tokens.emerald.border,
                        glowColor: tokens.emerald.icon,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ví Tài xế & Đối soát',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: tokens.ink,
                            ),
                          ),
                          Text(
                            'Chia sẻ cước tự động: 80% Tài xế · 20% Nền tảng',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: tokens.emerald.foreground,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Làm mới ví tài xế',
                    onPressed: _loading || _busy ? null : () => _load(),
                    icon: const GhstButtonIcon.glyph(
                      GhstActionKind.refresh,
                      size: 18,
                    ),
                  ),
                ],
              ),
              if (_loading) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(),
              ] else if (_error != null && _summary == null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    color: tokens.rose.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: balance >= 0 ? tokens.emerald.fill : tokens.amber.fill,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: balance >= 0
                          ? tokens.emerald.border
                          : tokens.amber.border,
                    ),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Số dư khả dụng',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: tokens.inkSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _vnd(balance),
                            key: const ValueKey('driver-wallet-balance-text'),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: balance >= 0
                                  ? tokens.emerald.foreground
                                  : tokens.amber.foreground,
                            ),
                          ),
                        ],
                      ),
                      if (locked > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.amber.fill,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: tokens.amber.border),
                          ),
                          child: Text(
                            'Đang khóa chờ rút: ${_vnd(locked)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: tokens.amber.foreground,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, c) {
                    final cols = c.maxWidth >= 560 ? 4 : 2;
                    final w = (c.maxWidth - 10 * (cols - 1)) / cols;
                    final stats = <(String, String, TonePair)>[
                      ('Thu nhập 80%', _vnd(earned), tokens.emerald),
                      ('Chiết khấu sàn 20%', _vnd(commission), tokens.violet),
                      ('Chuyến hoàn tất', '$deliveredCount chuyến', tokens.sapphire),
                      ('COD tiền mặt giữ', _vnd(codHeld), tokens.amber),
                    ];
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final s in stats)
                          Container(
                            width: w,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: s.$3.fill,
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(color: s.$3.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.$1,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: tokens.inkSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  s.$2,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: s.$3.foreground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Mức ký quỹ đảm bảo nhận đơn COD: ${_vnd(balance < 0 ? 0 : balance)} / ${_vnd(escrowTarget)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: tokens.inkSecondary,
                        ),
                      ),
                    ),
                    Text(
                      balance >= escrowTarget
                          ? 'Đủ ký quỹ chuẩn'
                          : 'Nên nạp bổ sung',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: balance >= escrowTarget
                            ? tokens.emerald.foreground
                            : tokens.amber.foreground,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: escrowRatio,
                    backgroundColor: tokens.cardSubtle,
                    color: balance >= escrowTarget
                        ? tokens.emerald.icon
                        : tokens.amber.icon,
                  ),
                ),
                if (_notice != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _notice!,
                    style: TextStyle(
                      color: tokens.emerald.foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: tokens.rose.foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('btn-driver-wallet-topup'),
                      onPressed: _busy ? null : _openTopupDialog,
                      icon: const GhstButtonIcon.glyph(
                        GhstActionKind.qr,
                        size: 16,
                      ),
                      label: const Text('Nạp ký quỹ VietQR'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('btn-driver-wallet-withdraw'),
                      onPressed: _busy
                          ? null
                          : () => _openBankOrWithdrawDialog(withdraw: true),
                      icon: const GhstButtonIcon.glyph(
                        GhstActionKind.download,
                        size: 16,
                      ),
                      label: const Text('Rút về Ngân hàng'),
                    ),
                    TextButton.icon(
                      key: const ValueKey('btn-driver-wallet-bank'),
                      onPressed: _busy
                          ? null
                          : () => _openBankOrWithdrawDialog(withdraw: false),
                      icon: const GhstButtonIcon.glyph(
                        GhstActionKind.edit,
                        size: 15,
                      ),
                      label: Text(
                        ('${_wallet['bank_account_no'] ?? ''}').isEmpty
                            ? 'Liên kết TK Ngân hàng'
                            : '${_wallet['bank_name']} · ${_wallet['bank_account_no']}',
                      ),
                    ),
                  ],
                ),
                if (pendingTopup != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.sapphire.fill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tokens.sapphire.border),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          'Lệnh nạp chờ duyệt: ${_vnd(pendingTopup['amount'])} · Mã: ${pendingTopup['transfer_code']}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tokens.sapphire.foreground,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _showQrForTopup(pendingTopup),
                          icon: const GhstButtonIcon.glyph(
                            GhstActionKind.qr,
                            size: 15,
                          ),
                          label: const Text('Mở lại VietQR'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        if (!widget.compact && _summary != null) ...[
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            segments: [
              const ButtonSegment(
                value: false,
                icon: GhstButtonIcon.glyph(GhstActionKind.receipt, size: 16),
                label: Text('Biến động 80/20'),
              ),
              ButtonSegment(
                value: true,
                icon: const GhstButtonIcon.glyph(
                  GhstActionKind.wallet,
                  size: 16,
                ),
                label: Text('Lệnh Nạp / Rút (${_requests.length})'),
              ),
            ],
            selected: {_requestsTab},
            onSelectionChanged: (v) => setState(() => _requestsTab = v.first),
          ),
          const SizedBox(height: 12),
          if (!_requestsTab)
            GhstLuminousCard(
              padding: const EdgeInsets.all(14),
              child: _ledger.isEmpty
                  ? Text(
                      'Chưa có biến động số dư. Khi hoàn thành chuyến giao, 80% cước vận chuyển sẽ tự động quyết toán vào ví.',
                      style: TextStyle(color: tokens.inkSecondary),
                    )
                  : Column(
                      children: [
                        for (final item in _ledger)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: GhstButtonIcon.glyph(
                              (item['delta'] as num? ?? 0) >= 0
                                  ? GhstActionKind.plus
                                  : GhstActionKind.minus,
                              size: 18,
                              color: (item['delta'] as num? ?? 0) >= 0
                                  ? tokens.emerald.foreground
                                  : tokens.amber.foreground,
                            ),
                            title: Text(
                              _ledgerLabel('${item['kind'] ?? ''}'),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: tokens.ink,
                              ),
                            ),
                            subtitle: Text(
                              '${item['note'] ?? ''} · ${_shortTime(item['created_at'])}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${(item['delta'] as num? ?? 0) >= 0 ? '+' : ''}${_vnd(item['delta'])}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: (item['delta'] as num? ?? 0) >= 0
                                        ? tokens.emerald.foreground
                                        : tokens.rose.foreground,
                                  ),
                                ),
                                Text(
                                  'Dư: ${_vnd(item['balance_after'])}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: tokens.inkSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            )
          else
            GhstLuminousCard(
              padding: const EdgeInsets.all(14),
              child: _requests.isEmpty
                  ? Text(
                      'Chưa có lệnh nạp ký quỹ hoặc rút thu nhập.',
                      style: TextStyle(color: tokens.inkSecondary),
                    )
                  : Column(
                      children: [
                        for (final req in _requests)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      '${req['kind'] == 'topup' ? 'Nạp ký quỹ VietQR' : 'Rút về ngân hàng'} · ${_vnd(req['amount'])}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: tokens.ink,
                                      ),
                                    ),
                                    _RequestStateChip(
                                      state: '${req['state'] ?? 'pending'}',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  req['kind'] == 'topup'
                                      ? 'Nội dung CK: ${req['transfer_code']} · ${_shortTime(req['created_at'])}'
                                      : 'NH nhận: ${req['bank_name']} · ${req['bank_account_no']} (${req['bank_account_name']}) · ${_shortTime(req['created_at'])}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: tokens.inkSecondary,
                                  ),
                                ),
                                if ('${req['admin_note'] ?? ''}'
                                    .trim()
                                    .isNotEmpty)
                                  Text(
                                    'Phản hồi đối soát: ${req['admin_note']}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: tokens.sapphire.foreground,
                                    ),
                                  ),
                                if (req['state'] == 'pending') ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      if (req['kind'] == 'topup')
                                        OutlinedButton.icon(
                                          onPressed: () => _showQrForTopup(req),
                                          icon: const GhstButtonIcon.glyph(
                                            GhstActionKind.qr,
                                            size: 15,
                                          ),
                                          label: const Text('Hiện mã VietQR'),
                                        ),
                                      TextButton.icon(
                                        onPressed: _busy
                                            ? null
                                            : () => _cancelRequest(req),
                                        icon: const GhstButtonIcon.glyph(
                                          GhstActionKind.close,
                                          size: 15,
                                        ),
                                        label: const Text('Hủy yêu cầu'),
                                      ),
                                    ],
                                  ),
                                ],
                                const Divider(),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
        ],
      ],
    );
  }
}

class _RequestStateChip extends StatelessWidget {
  const _RequestStateChip({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final (label, pair) = switch (state) {
      'approved' => ('Đã duyệt', tokens.emerald),
      'rejected' => ('Từ chối', tokens.rose),
      'cancelled' => ('Đã hủy', tokens.violet),
      _ => ('Chờ duyệt', tokens.amber),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: pair.fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: pair.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: pair.foreground,
        ),
      ),
    );
  }
}

class AdminDriverWalletRequestsSection extends StatefulWidget {
  const AdminDriverWalletRequestsSection({
    super.key,
    required this.session,
    required this.lease,
  });

  final CloudAccountSession session;
  final CloudSessionLease lease;

  @override
  State<AdminDriverWalletRequestsSection> createState() =>
      _AdminDriverWalletRequestsSectionState();
}

class _AdminDriverWalletRequestsSectionState
    extends State<AdminDriverWalletRequestsSection> {
  String _stateFilter = 'pending';
  String _kindFilter = 'all';
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _requests = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!widget.lease.valid) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.session.service.driverWallet('admin_list', {
        'state': _stateFilter,
        'kind': _kindFilter,
      });
      if (!mounted || !widget.lease.valid) return;
      setState(() {
        _summary = res['kpis'] is Map
            ? Map<String, dynamic>.from(res['kpis'] as Map)
            : null;
        _requests = (res['requests'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted || widget.lease.handleAccessFailure(e)) return;
      setState(() {
        _loading = false;
        _error = e is PublicApiException
            ? e.message
            : 'Chưa tải được danh sách đối soát ví tài xế.';
      });
    }
  }

  Future<void> _resolve(Map<String, dynamic> req, String decision) async {
    if (_busy || !widget.lease.valid) return;
    final noteCtrl = TextEditingController();
    final approve = decision == 'approve';
    final confirmedNote = await showDialog<String>(
      context: context,
      builder: (_) => CloudSessionBoundary(
        session: widget.session,
        operator: true,
        dialog: true,
        builder: (dialogCtx, _) => AlertDialog(
          title: Text(
            approve
                ? (req['kind'] == 'topup'
                      ? 'Xác nhận đã nhận tiền nạp VietQR'
                      : 'Xác nhận đã chuyển khoản rút tiền')
                : 'Từ chối yêu cầu ví tài xế',
          ),
          content: SizedBox(
            width: 400,
            child: TextField(
              controller: noteCtrl,
              maxLength: 300,
              decoration: InputDecoration(
                labelText: approve
                    ? 'Mã tham chiếu ngân hàng / Ghi chú đối soát'
                    : 'Lý do từ chối (tối thiểu 3 ký tự)',
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(dialogCtx),
              icon: const GhstButtonIcon.glyph(GhstActionKind.close, size: 16),
              label: const Text('Hủy'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogCtx, noteCtrl.text.trim()),
              icon: GhstButtonIcon.glyph(
                approve ? GhstActionKind.checkCircle : GhstActionKind.warning,
                size: 16,
              ),
              label: Text(approve ? 'Phê duyệt' : 'Từ chối'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 200), noteCtrl.dispose);
    if (confirmedNote == null || !widget.lease.valid) return;
    if (!approve && confirmedNote.length < 3) {
      setState(() => _error = 'Cần nhập lý do từ chối tối thiểu 3 ký tự.');
      return;
    }
    final effectiveNote = confirmedNote.length >= 3
        ? confirmedNote
        : 'Đã đối soát xác nhận';

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.service.driverWallet('admin_resolve', {
        'request_id': req['id'],
        'decision': decision,
        'admin_note': effectiveNote,
      });
      await _load();
    } catch (e) {
      if (!mounted || widget.lease.handleAccessFailure(e)) return;
      setState(() {
        _error = e is PublicApiException
            ? e.message
            : 'Chưa xử lý được yêu cầu ví tài xế.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GhstThemeTokens.of(context);
    final pendingTopup = (_summary?['pending_topups'] as num? ?? 0).toInt();
    final pendingWithdraw =
        (_summary?['pending_withdrawals'] as num? ?? 0).toInt();
    final totalCommission =
        (_summary?['total_platform_commission'] as num? ?? 0).toInt();
    final totalBalance =
        (_summary?['total_driver_balances'] as num? ?? 0).toInt();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GhstLuminousCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          Text(
                            'Đối soát Nạp ký quỹ VietQR & Rút Ngân hàng Tài xế · Tổng số dư ví: ${_vnd(totalBalance)} · Chiết khấu sàn 20%: ${_vnd(totalCommission)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: tokens.ink,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Làm mới danh sách',
                            onPressed: _loading || _busy ? null : _load,
                            icon: const GhstButtonIcon.glyph(
                              GhstActionKind.refresh,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in [
                            ('pending', 'Chờ duyệt (${pendingTopup + pendingWithdraw})'),
                            ('approved', 'Đã duyệt'),
                            ('rejected', 'Từ chối'),
                            ('all', 'Tất cả'),
                          ])
                            ChoiceChip(
                              showCheckmark: false,
                              avatar: const GhstButtonIcon.glyph(
                                GhstActionKind.wallet,
                                size: 14,
                              ),
                              label: Text(s.$2),
                              selected: _stateFilter == s.$1,
                              onSelected: _busy
                                  ? null
                                  : (_) {
                                      setState(() => _stateFilter = s.$1);
                                      unawaited(_load());
                                    },
                            ),
                          for (final k in [
                            ('all', 'Mọi loại lệnh'),
                            ('topup', 'Nạp VietQR ($pendingTopup)'),
                            ('withdraw', 'Rút NH ($pendingWithdraw)'),
                          ])
                            FilterChip(
                              showCheckmark: false,
                              avatar: GhstButtonIcon.glyph(
                                k.$1 == 'withdraw'
                                    ? GhstActionKind.download
                                    : GhstActionKind.qr,
                                size: 14,
                              ),
                              label: Text(k.$2),
                              selected: _kindFilter == k.$1,
                              onSelected: _busy
                                  ? null
                                  : (_) {
                                      setState(() => _kindFilter = k.$1);
                                      unawaited(_load());
                                    },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading || _busy) const LinearProgressIndicator(),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: tokens.rose.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (!_loading && _requests.isEmpty && _error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        'Không có yêu cầu nạp / rút ví tài xế trong bộ lọc này.',
                        style: TextStyle(color: tokens.inkSecondary),
                      ),
                    ),
                  ),
                for (final req in _requests)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: GhstLuminousCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Text(
                                '${req['kind'] == 'topup' ? 'NẠP KÝ QUỸ VIETQR' : 'RÚT VỀ NGÂN HÀNG'} · ${_vnd(req['amount'])}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: tokens.ink,
                                ),
                              ),
                              _RequestStateChip(
                                state: '${req['state'] ?? 'pending'}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tài xế: ${req['driver_name'] ?? ''} · SĐT: ${req['driver_phone'] ?? ''} · Số dư hiện tại: ${_vnd(req['driver_balance'])} (Đang khóa: ${_vnd(req['driver_locked_balance'])})',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: tokens.inkSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            req['kind'] == 'topup'
                                ? 'Mã đối soát chuyển khoản: ${req['transfer_code']} · Tạo lúc ${_shortTime(req['created_at'])}'
                                : 'Thụ hưởng: ${req['bank_name']} (${req['bank_bin']}) · STK: ${req['bank_account_no']} · Chủ TK: ${req['bank_account_name']} · Tạo lúc ${_shortTime(req['created_at'])}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          if ('${req['driver_note'] ?? ''}'.trim().isNotEmpty)
                            Text('Ghi chú tài xế: ${req['driver_note']}'),
                          if ('${req['admin_note'] ?? ''}'.trim().isNotEmpty)
                            Text(
                              'Ghi chú duyệt: ${req['admin_note']}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: tokens.sapphire.foreground,
                              ),
                            ),
                          if (req['state'] == 'pending') ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  key: ValueKey(
                                    'admin-wallet-approve-${req['id']}',
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _resolve(req, 'approve'),
                                  icon: const GhstButtonIcon.glyph(
                                    GhstActionKind.checkCircle,
                                    size: 16,
                                  ),
                                  label: Text(
                                    req['kind'] == 'topup'
                                        ? 'Xác nhận đã nhận tiền'
                                        : 'Xác nhận đã chuyển khoản',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  key: ValueKey(
                                    'admin-wallet-reject-${req['id']}',
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _resolve(req, 'reject'),
                                  icon: const GhstButtonIcon.glyph(
                                    GhstActionKind.close,
                                    size: 16,
                                  ),
                                  label: const Text('Từ chối'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
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
