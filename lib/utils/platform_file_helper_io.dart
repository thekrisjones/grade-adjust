import 'dart:io';

Future<String> saveTextFile(String fileName, String contents) async {
  final baseDir = Directory.current.path;
  final dir = Directory(baseDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');
  await file.writeAsString(contents);
  return file.path;
}

Future<String> saveBytesFile(String fileName, List<int> bytes) async {
  final baseDir = Directory.current.path;
  final dir = Directory(baseDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes);
  return file.path;
}

Future<String> readTextFile({String? path, List<int>? bytes}) async {
  if (bytes != null) {
    return String.fromCharCodes(bytes);
  }
  if (path == null || path.isEmpty) {
    throw const FormatException('No file path available to read');
  }
  return await File(path).readAsString();
}
