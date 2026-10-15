sealed class AppException implements Exception {
  final String message;
  final String code;

  const AppException({
    required this.message,
    required this.code,
  });

  @override
  String toString() => '[$code] $message';
}

final class DatabaseException extends AppException {
  const DatabaseException({
    required super.message,
    super.code = 'DB_ERROR',
  });
}

final class NetworkSyncException extends AppException {
  const NetworkSyncException({
    required super.message,
    super.code = 'NET_SYNC_ERROR',
  });
}

final class GpsIntegrityException extends AppException {
  final String ruleId;

  const GpsIntegrityException({
    required this.ruleId,
    required super.message,
  }) : super(code: ruleId);
}

final class InvalidOrderStateTransitionException extends AppException {
  final String fromState;
  final String toState;

  const InvalidOrderStateTransitionException({
    required this.fromState,
    required this.toState,
  }) : super(
          code: 'INVALID_FSM_TRANSITION',
          message: 'Không thể chuyển trạng thái đơn hàng từ $fromState sang $toState.',
        );
}

final class ValidationException extends AppException {
  const ValidationException({
    required super.message,
    super.code = 'VALIDATION_ERROR',
  });
}
