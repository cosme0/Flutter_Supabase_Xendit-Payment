import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'screens/product_list_screen.dart';
import 'services/app_bootstrap.dart';

/// Entry point of the student shop application.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppBootstrap.initialize();
  runApp(const StudentShopApp());
}

/// Root widget of the student shop.
class StudentShopApp extends StatelessWidget {
  const StudentShopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: AppBootstrap.isReady
          ? const ProductListScreen()
          : const ConfigurationRequiredScreen(),
    );
  }

  static ThemeData _buildTheme() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1B4DB1),
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
    );
  }
}

/// Shown when the application was started without a Supabase configuration.
class ConfigurationRequiredScreen extends StatelessWidget {
  const ConfigurationRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(AppConfig.appName)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.settings_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Configuration required',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                AppBootstrap.errorMessage ??
                    'The Supabase configuration is missing.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '# .env (copy it from .env.example)\n'
                  'SUPABASE_URL=https://<project-ref>.supabase.co\n'
                  'SUPABASE_PUBLISHABLE_KEY=<publishable key>\n\n'
                  '# then start the app again\n'
                  'flutter run --dart-define-from-file=.env\n\n'
                  '# build the apk\n'
                  'flutter build apk --release --dart-define-from-file=.env',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
