import 'dart:io';

/// Reads a `KEY=VALUE` file (dotenv format) and returns the values.
///
/// Returns `null` when the file does not exist. Lines that start with `#` are
/// comments, empty lines are ignored and the values may be quoted.
Map<String, String>? readEnvFile(String path) {
  try {
    final File file = File(path);
    if (!file.existsSync()) return null;

    final Map<String, String> values = <String, String>{};
    for (final String rawLine in file.readAsLinesSync()) {
      final String line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final int separator = line.indexOf('=');
      if (separator <= 0) continue;

      final String key = line.substring(0, separator).trim();
      String value = line.substring(separator + 1).trim();
      if (value.length > 1 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (key.isNotEmpty) values[key] = value;
    }
    return values;
  } catch (_) {
    return null;
  }
}
