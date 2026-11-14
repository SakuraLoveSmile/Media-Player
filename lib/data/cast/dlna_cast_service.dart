import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dlna_device.dart';

/// Network primitives the cast service needs, injected so the protocol logic
/// (SSDP parsing, SOAP envelopes) is unit-testable without a real LAN.
abstract class DlnaTransport {
  /// Sends an SSDP M-SEARCH for media renderers and collects the lower-cased
  /// response headers (`location`, `usn`, `st`) until [timeout] elapses.
  Future<List<Map<String, String>>> search(Duration timeout);

  /// Fetches a device description document.
  Future<String> get(String url);

  /// Posts a SOAP [body] to [url] with the AVTransport [action] name.
  Future<void> post(String url, String action, String body);
}

/// Discovery + AVTransport control for DLNA media renderers (S19). Chromecast
/// is intentionally out of scope: it needs the proprietary Google Cast SDK.
abstract class DlnaCastService {
  Future<List<DlnaDevice>> discover({
    Duration timeout = const Duration(seconds: 3),
  });

  /// Points the renderer at [url] and starts playback.
  Future<void> cast(DlnaDevice device, String url, {String title = ''});

  Future<void> stop(DlnaDevice device);
  Future<void> pause(DlnaDevice device);
  Future<void> play(DlnaDevice device);
}

class DlnaCastServiceImpl implements DlnaCastService {
  DlnaCastServiceImpl({DlnaTransport? transport})
    : _transport = transport ?? IoDlnaTransport();

  final DlnaTransport _transport;

  static const String _serviceType =
      'urn:schemas-upnp-org:service:AVTransport:1';

  @override
  Future<List<DlnaDevice>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final responses = await _transport.search(timeout);
    final devices = <DlnaDevice>[];
    final seen = <String>{};
    for (final headers in responses) {
      final location = headers['location'];
      if (location == null || location.isEmpty) continue;
      final id = headers['usn'] ?? location;
      if (!seen.add(id)) continue;
      try {
        final description = await _transport.get(location);
        final device = parseDevice(description, location, id);
        if (device != null) devices.add(device);
      } catch (_) {
        // A renderer that answered SSDP but serves no usable description is
        // skipped, never fatal to the whole scan.
        continue;
      }
    }
    return devices;
  }

  @override
  Future<void> cast(DlnaDevice device, String url, {String title = ''}) async {
    await _transport.post(
      device.controlUrl,
      'SetAVTransportURI',
      _setUriBody(url, title),
    );
    await _transport.post(device.controlUrl, 'Play', _playBody);
  }

  @override
  Future<void> stop(DlnaDevice device) =>
      _transport.post(device.controlUrl, 'Stop', _instanceBody('Stop'));

  @override
  Future<void> pause(DlnaDevice device) =>
      _transport.post(device.controlUrl, 'Pause', _instanceBody('Pause'));

  @override
  Future<void> play(DlnaDevice device) =>
      _transport.post(device.controlUrl, 'Play', _playBody);

  /// Builds a [DlnaDevice] from a UPnP description document, or null when it
  /// exposes no AVTransport service. Exposed for tests.
  static DlnaDevice? parseDevice(String xml, String location, String id) {
    final controlPath = _avTransportControlUrl(xml);
    if (controlPath == null) return null;
    final base = Uri.parse(location);
    final controlUrl = base.resolve(controlPath).toString();
    final name = _firstTag(xml, 'friendlyName');
    return DlnaDevice(
      id: id,
      name: (name == null || name.isEmpty) ? base.host : _unescape(name),
      controlUrl: controlUrl,
      address: base.authority,
    );
  }

  static String? _avTransportControlUrl(String xml) {
    final services = RegExp(r'<service>([\s\S]*?)</service>').allMatches(xml);
    for (final match in services) {
      final block = match.group(1) ?? '';
      final type = _firstTag(block, 'serviceType') ?? '';
      if (!type.contains('AVTransport')) continue;
      final control = _firstTag(block, 'controlURL');
      if (control != null && control.isNotEmpty) return control.trim();
    }
    return null;
  }

  static String? _firstTag(String xml, String tag) {
    final match = RegExp('<$tag>([\\s\\S]*?)</$tag>').firstMatch(xml);
    return match?.group(1)?.trim();
  }

  static String _setUriBody(String url, String title) {
    final didl =
        '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<item id="0" parentID="0" restricted="1">'
        '<dc:title>${_escape(title)}</dc:title>'
        '<upnp:class>object.item.videoItem</upnp:class>'
        '</item></DIDL-Lite>';
    return _envelope(
      'SetAVTransportURI',
      '<InstanceID>0</InstanceID>'
          '<CurrentURI>${_escape(url)}</CurrentURI>'
          '<CurrentURIMetaData>${_escape(didl)}</CurrentURIMetaData>',
    );
  }

  static const String _playBody = '<InstanceID>0</InstanceID><Speed>1</Speed>';

  static String _instanceBody(String action) =>
      _envelope(action, '<InstanceID>0</InstanceID>');

  static String _envelope(String action, String inner) =>
      '<?xml version="1.0" encoding="utf-8"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
      '<s:Body><u:$action xmlns:u="$_serviceType">$inner</u:$action></s:Body>'
      '</s:Envelope>';

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _unescape(String value) => value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// Real LAN transport: SSDP over UDP multicast, descriptions and SOAP over
/// HTTP. M-SEARCH responses are unicast back to the sender, so no multicast
/// group membership (or Android MulticastLock) is required to receive them.
class IoDlnaTransport implements DlnaTransport {
  IoDlnaTransport({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;
  static const String _group = '239.255.255.250';
  static const int _port = 1900;

  @override
  Future<List<Map<String, String>>> search(Duration timeout) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final results = <Map<String, String>>[];
    final done = Completer<void>();
    const message =
        'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $_group:$_port\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 2\r\n'
        'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n';
    final sub = socket.listen((RawSocketEvent event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      final text = utf8.decode(datagram.data, allowMalformed: true);
      final headers = parseSsdpHeaders(text);
      if (headers.containsKey('location')) results.add(headers);
    });
    socket.send(utf8.encode(message), InternetAddress(_group), _port);
    final timer = Timer(timeout, () {
      if (!done.isCompleted) done.complete();
    });
    try {
      await done.future;
    } finally {
      timer.cancel();
      await sub.cancel();
      socket.close();
    }
    return results;
  }

  @override
  Future<String> get(String url) async {
    final request = await _client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'device description ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }
    return response.transform(utf8.decoder).join();
  }

  @override
  Future<void> post(String url, String action, String body) async {
    final request = await _client.postUrl(Uri.parse(url));
    request.headers.set('Content-Type', 'text/xml; charset=utf-8');
    request.headers.set(
      'SOAPAction',
      '"urn:schemas-upnp-org:service:AVTransport:1#$action"',
    );
    request.add(utf8.encode(body));
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'SOAP $action ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }
  }

  /// Parses an SSDP HTTPU response into lower-cased header keys. Exposed for
  /// tests.
  static Map<String, String> parseSsdpHeaders(String text) {
    final headers = <String, String>{};
    final lines = text.split(RegExp(r'\r?\n'));
    for (final line in lines.skip(1)) {
      final index = line.indexOf(':');
      if (index <= 0) continue;
      final key = line.substring(0, index).trim().toLowerCase();
      final value = line.substring(index + 1).trim();
      if (key.isNotEmpty) headers[key] = value;
    }
    return headers;
  }
}
