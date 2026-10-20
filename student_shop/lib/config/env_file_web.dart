/// The web build cannot read files from the file system, so the `.env` file
/// is only available on the platforms that support `dart:io`.
Map<String, String>? readEnvFile(String path) => null;
