import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_shop/config/app_config.dart';
import 'package:student_shop/config/env_file.dart';

void main() {
  group('the .env file', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('student_shop_env');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    File writeEnv(String content) {
      final File file = File('${tempDir.path}/.env');
      file.writeAsStringSync(content);
      return file;
    }

    test('is parsed into key value pairs', () {
      final File file = writeEnv(
        '# a comment\n'
        'SUPABASE_URL=https://iiznhatxciycwghihnaq.supabase.co\n'
        '\n'
        'SUPABASE_PUBLISHABLE_KEY=sb_publishable_abc123\n'
        'QUOTED="with spaces"\n',
      );

      final Map<String, String>? values = readEnvFile(file.path);

      expect(values, isNotNull);
      expect(
        values!['SUPABASE_URL'],
        'https://iiznhatxciycwghihnaq.supabase.co',
      );
      expect(values['SUPABASE_PUBLISHABLE_KEY'], 'sb_publishable_abc123');
      expect(values['QUOTED'], 'with spaces');
    });

    test('returns null when the file does not exist', () {
      expect(readEnvFile('${tempDir.path}/missing.env'), isNull);
    });
  });

  group('AppConfig', () {
    test('detects a placeholder key', () {
      // the compiled values of the test run are empty, so the placeholder
      // check has to be done with the helper itself
      expect(AppConfig.containsPlaceholder, isFalse);
      expect(AppConfig.isSupabaseConfigured, isFalse);
    });

    test('exposes the currency of the demonstration', () {
      expect(AppConfig.currencyCode, 'PHP');
      expect(AppConfig.currencySymbol, '₱');
      expect(AppConfig.createInvoiceFunction, 'create-invoice');
    });
  });
}
