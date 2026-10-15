import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/env_config.dart';
import 'core/theme/app_theme.dart';
import 'presentation/bloc/system_architecture_cubit.dart';
import 'presentation/screens/architecture_dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (EnvConfig.isSupabaseConfigured) {
    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      publishableKey: EnvConfig.supabaseAnonKey,
    );
  }

  runApp(const GpsDeliveryApp());
}

class GpsDeliveryApp extends StatelessWidget {
  const GpsDeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SystemArchitectureCubit(),
      child: MaterialApp(
        title: 'GiaoHang GPS - Đa Nền Tảng',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const ArchitectureDashboardScreen(),
      ),
    );
  }
}
