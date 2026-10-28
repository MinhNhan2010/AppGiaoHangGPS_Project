import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env_config.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/local/app_state_store.dart';
import 'data/datasources/local/sqlite_offline_queue_datasource.dart';
import 'presentation/bloc/system_architecture_cubit.dart';
import 'presentation/screens/architecture_dashboard_screen.dart';
import 'presentation/screens/admin_portal_screen.dart';
import 'presentation/screens/public_order_tracking_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SqliteOfflineQueueDatasource.ensureDesktopFfiInitialized();

  if (EnvConfig.isSupabaseConfigured) {
    try {
      await Supabase.initialize(
        url: EnvConfig.supabaseUrl,
        publishableKey: EnvConfig.supabaseAnonKey,
      );
    } catch (_) {
      AppStateStore.instance.isOfflineMode = true;
    }
  }

  try {
    await AppStateStore.instance.initializeDatabase();
  } catch (_) {}
  runApp(const GpsDeliveryApp());
}

class GpsDeliveryApp extends StatelessWidget {
  final String? initialRoute;
  const GpsDeliveryApp({super.key, this.initialRoute});

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
            data: media.copyWith(textScaler: TextScaler.linear(scaleFactor)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        initialRoute:
            initialRoute ??
            (Uri.base.path == '/admin' ||
                    Uri.base.path == '/admin/' ||
                    Uri.base.fragment == '/admin' ||
                    Uri.base.fragment == '/admin/'
                ? '/admin'
                : (Uri.base.fragment.startsWith('/track')
                      ? Uri.base.fragment
                      : (Uri.base.path == '/track' || Uri.base.path == '/track/'
                            ? (Uri.base.query.isNotEmpty
                                  ? '/track?${Uri.base.query}'
                                  : '/track')
                            : null))),
        onGenerateInitialRoutes: (name) => [
          MaterialPageRoute<void>(
            settings: RouteSettings(name: name),
            builder: (_) {
              if (name == '/admin') {
                return const AdminPortalScreen();
              }
              if (name == '/track' || name.startsWith('/track?')) {
                return PublicOrderTrackingScreen(
                  initialQuery:
                      PublicOrderTrackingScreen.extractQueryFromRouteName(name),
                );
              }
              return const ArchitectureDashboardScreen();
            },
          ),
        ],
        routes: {
          '/': (_) => const ArchitectureDashboardScreen(),
          '/admin': (_) => const AdminPortalScreen(),
          '/track': (_) => const PublicOrderTrackingScreen(),
        },
        onGenerateRoute: (settings) {
          final routeName = settings.name ?? '';
          if (routeName == '/track' || routeName.startsWith('/track?')) {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => PublicOrderTrackingScreen(
                initialQuery:
                    PublicOrderTrackingScreen.extractQueryFromRouteName(
                      routeName,
                    ),
              ),
            );
          }
          return null;
        },
      ),
    );
  }
}
