import 'package:flutter_test/flutter_test.dart';
import 'package:student_shop/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('points at the Supabase project of the demonstration', () {
      expect(AppConfig.supabaseUrl, 'https://kfvxqsxycpmawgbwugyr.supabase.co');
      expect(AppConfig.supabaseUrl.startsWith('https://'), isTrue);
    });

    test('uses a public anon key that is not a placeholder', () {
      expect(AppConfig.supabaseKey, isNotEmpty);
      expect(AppConfig.supabaseKey.contains('YOUR_'), isFalse);
      expect(AppConfig.supabaseKey.contains('PASTE'), isFalse);
    });

    test('reports that the app is configured', () {
      expect(AppConfig.isSupabaseConfigured, isTrue);
    });

    test('knows the name of the invoice edge function', () {
      expect(AppConfig.createInvoiceFunction, 'create-invoice');
    });
  });
}
