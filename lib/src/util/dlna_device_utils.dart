import 'dart:io';
import 'dart:convert';
import 'package:xml/xml.dart';

/// 解析 DLNA description.xml，取得 AVTransport controlURL
Future<String?> fetchAvTransportControlUrl(String descriptionUrl) async {
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(descriptionUrl));
    final response = await request.close();
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join();
    final document = XmlDocument.parse(body);

    final services = document.findAllElements('service');
    for (final service in services) {
      final serviceType = service.getElement('serviceType')?.value ?? '';
      if (serviceType.contains('AVTransport')) {
        final controlUrl = service.getElement('controlURL')?.value;
        if (controlUrl != null && controlUrl.isNotEmpty) {
          final uri = Uri.parse(descriptionUrl);
          return uri.resolve(controlUrl).toString();
        }
      }
    }
    return null;
  } catch (e) {
    print('[DLNA] fetchAvTransportControlUrl error: $e');
    return null;
  }
}

/// 解析 DLNA description.xml，取得 RenderingControl controlURL
Future<String?> fetchRenderingControlUrl(String descriptionUrl) async {
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(descriptionUrl));
    final response = await request.close();
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join();
    final document = XmlDocument.parse(body);

    final services = document.findAllElements('service');
    for (final service in services) {
      final serviceType = service.getElement('serviceType')?.value ?? '';
      if (serviceType.contains('RenderingControl')) {
        final controlUrl = service.getElement('controlURL')?.value;
        if (controlUrl != null && controlUrl.isNotEmpty) {
          final uri = Uri.parse(descriptionUrl);
          return uri.resolve(controlUrl).toString();
        }
      }
    }
    return null;
  } catch (e) {
    print('[DLNA] fetchRenderingControlUrl error: $e');
    return null;
  }
}
Future<List<String?>> fetchControlUrls(String descriptionUrl) async {
  final output = <String?>[null, null];
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(descriptionUrl));
    final response = await request.close();
    if (response.statusCode != 200) return [];
    final body = await response.transform(utf8.decoder).join();
    final document = XmlDocument.parse(body);

    final services = document.findAllElements('service');
    for (final service in services) {
      final serviceType = service.getElement('serviceType')?.value ?? '';
      final controlUrl = service.getElement('controlURL')?.value;
      if (controlUrl != null && controlUrl.isNotEmpty) {
        final uri = Uri.parse(descriptionUrl);
        if (serviceType.contains('AVTransport')) {
          output[0] = uri.resolve(controlUrl).toString();
        }
        if (serviceType.contains('RenderingControl')) {
          output[1] = uri.resolve(controlUrl).toString();
        }
      }
    }
  } catch (e) {
    print('[DLNA] fetchControlUrls error: $e');
  }
  return output;
}