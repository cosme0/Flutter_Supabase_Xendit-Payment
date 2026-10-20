/// Reads a dotenv file - only available on platforms with `dart:io`.
///
/// The conditional import keeps the web build working.
library;

export 'env_file_web.dart' if (dart.library.io) 'env_file_io.dart';
