import 'package:flutter/services.dart';

class SurveyExportPlatform {
  const SurveyExportPlatform();

  static const _channel = MethodChannel('com.toposurvey.toposurvey/export');

  Future<String?> saveFile({
    required String fileName,
    required String mimeType,
    required Object content,
  }) => _channel.invokeMethod<String>('createDocument', {
    'fileName': fileName,
    'mimeType': mimeType,
    'content': content,
  });
}
