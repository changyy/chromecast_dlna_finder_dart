import 'dart:convert';
import 'dart:io';
import 'package:xml/xml.dart';

/// DLNA/UPnP SOAP 輔助工具
class DlnaSoapUtil {
  /// 發送 SOAP 請求
  /// [controlUrl] 控制端點 (renderer 的 AVTransport/RenderingControl)
  /// [serviceType] 服務類型 (如 urn:schemas-upnp-org:service:AVTransport:1)
  /// [action] 動作名稱 (如 Play, Pause, SetAVTransportURI)
  /// [args] 參數 (`Map<String, dynamic>`)
  static Future<Map<String, dynamic>> sendSoap({
    required String controlUrl,
    required String serviceType,
    required String action,
    required Map<String, dynamic> args,
  }) async {
    final envelope = _buildSoapEnvelope(serviceType, action, args);
    final headers = {
      'Content-Type': 'text/xml; charset="utf-8"',
      'SOAPAction': '"$serviceType#$action"',
      'Connection': 'keep-alive',
    };
    final client = HttpClient();
    final request = await client.postUrl(Uri.parse(controlUrl));
    headers.forEach(request.headers.set);
    request.write(envelope);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    client.close(force: true);
    if (response.statusCode != 200) {
      throw Exception('SOAP Error: ${response.statusCode}\n$responseBody');
    }
    return _parseSoapResponse(responseBody, action);
  }

  static String _buildSoapEnvelope(String serviceType, String action, Map<String, dynamic> args) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.writeln('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">');
    buffer.writeln('<s:Body>');
    buffer.writeln('<u:$action xmlns:u="$serviceType">');
    args.forEach((k, v) {
      var value = v;
      if (k == 'InstanceID') value = v.toString();
      buffer.writeln('<$k>$value</$k>');
    });
    buffer.writeln('</u:$action>');
    buffer.writeln('</s:Body>');
    buffer.writeln('</s:Envelope>');
    return buffer.toString();
  }

  static Map<String, dynamic> _parseSoapResponse(String xmlString, String action) {
    final document = XmlDocument.parse(xmlString);
    final result = <String, dynamic>{};
    // 嘗試取得 `u:${action}Response` 下所有子元素
    final body = document.findAllElements('s:Body').isEmpty
        ? document.rootElement
        : document.findAllElements('s:Body').first;
    final resp = body.descendants.whereType<XmlElement>().firstWhere(
      (e) => e.name.local.endsWith('${action}Response'),
      orElse: () => XmlElement(XmlName('empty')),
    );
    if (resp.name.local == 'empty') return result;
    for (final child in resp.children.whereType<XmlElement>()) {
      result[child.name.local] = child.value;
    }
    return result;
  }
}
