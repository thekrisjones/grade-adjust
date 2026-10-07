import 'dart:html' as html;

Future<String> saveTextFile(String fileName, String contents) async {
  final blob = html.Blob([contents], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..style.display = 'none'
    ..download = fileName;
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return fileName;
}

Future<String> saveBytesFile(String fileName, List<int> bytes) async {
  final blob = html.Blob([bytes], 'application/octet-stream');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..style.display = 'none'
    ..download = fileName;
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return fileName;
}

Future<String> readTextFile({String? path, List<int>? bytes}) async {
  if (bytes != null) {
    return String.fromCharCodes(bytes);
  }
  if (path == null || path.isEmpty) {
    throw const FormatException('No file path available to read');
  }
  throw UnsupportedError('Reading direct file paths is not supported in the browser runtime');
}
