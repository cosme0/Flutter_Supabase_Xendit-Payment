import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'screens/product_list_screen.dart';

void main() {
  // The user interface is rendered first, so the app always starts - even if
  // Supabase cannot be reached. The store shows the real error message.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StudentEcommerceApp());
}

class StudentEcommerceApp extends StatelessWidget {
  const StudentEcommerceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConfig.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ProductListScreen(),
    );
  }
}
