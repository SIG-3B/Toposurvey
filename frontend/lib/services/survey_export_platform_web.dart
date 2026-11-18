import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class SurveyExportPlatform {
  const SurveyExportPlatform();

  Future<String?> saveFile({
    required String fileName,
    required String mimeType,
    required Object content,
  }) async {
    final bytes = content is String
        ? Uint8List.fromList(utf8.encode(content))
        : Uint8List.fromList(content as List<int>);
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return fileName;
  }
}
