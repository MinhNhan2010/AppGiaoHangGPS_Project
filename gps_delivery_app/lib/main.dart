import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/env_config.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/local/app_state_store.dart';
import 'data/datasources/local/sqlite_offline_queue_datasource.dart';
import 'presentation/bloc/system_architecture_cubit.dart';
import 'presentation/screens/architecture_dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SqliteOfflineQueueDatasource.ensureDesktopFfiInitialized();

  if (EnvConfig.isSupabaseConfigured) {
    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      publishableKey: EnvConfig.supabaseAnonKey,
    );
  }

  runApp(const GpsDeliveryApp());
  await AppStateStore.instance.initializeDatabase();
}

class GpsDeliveryApp extends StatelessWidget {
  const GpsDeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SystemArchitectureCubit(),
      child: MaterialApp(
        title: 'Giao Hàng Siêu Tốc (GHST) - Định Vị GPS Đa Nền Tảng',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final size = media.size;
          final shortest = size.shortestSide;
          final scaleFactor = shortest <= 0
              ? 1.0
              : (shortest / 390.0).clamp(0.86, 1.0);
          return MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(scaleFactor),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const ArchitectureDashboardScreen(),
      ),
    );
  }
}
