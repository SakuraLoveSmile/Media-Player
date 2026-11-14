import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/cast/dlna_cast_service.dart';
import 'package:media_player/data/cast/dlna_device.dart';

class FakeDlnaTransport implements DlnaTransport {
  List<Map<String, String>> responses = <Map<String, String>>[];
  Map<String, String> descriptions = <String, String>{};
  Object? searchError;
  final List<String> gets = <String>[];
  final List<({String url, String action, String body})> posts =
      <({String url, String action, String body})>[];

  @override
  Future<List<Map<String, String>>> search(Duration timeout) async {
    if (searchError != null) throw searchError!;
    return responses;
  }

  @override
  Future<String> get(String url) async {
    gets.add(url);
    final description = descriptions[url];
    if (description == null) throw StateError('no description for $url');
    return description;
  }

  @override
  Future<void> post(String url, String action, String body) async {
    posts.add((url: url, action: action, body: body));
  }
}

const _description = '''
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <friendlyName>客厅电视</friendlyName>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>/RenderingControl/control</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/AVTransport/control</controlURL>
      </service>
    </serviceList>
  </device>
</root>
''';

const _location = 'http://192.168.0.5:8080/desc.xml';

DlnaDevice _device() => const DlnaDevice(
  id: 'uuid:abc',
  name: '客厅电视',
  controlUrl: 'http://192.168.0.5:8080/AVTransport/control',
  address: '192.168.0.5:8080',
);

void main() {
  group('parseSsdpHeaders', () {
    test('lower-cases keys and skips the status line', () {
      final headers = IoDlnaTransport.parseSsdpHeaders(
        'HTTP/1.1 200 OK\r\n'
        'LOCATION: $_location\r\n'
        'USN: uuid:abc::urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
        'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n',
      );
      expect(headers['location'], _location);
      expect(headers['usn'], startsWith('uuid:abc'));
      expect(headers.containsKey('http/1.1 200 ok'), isFalse);
    });
  });

  group('parseDevice', () {
    test('extracts the name and resolves the AVTransport control URL', () {
      final device = DlnaCastServiceImpl.parseDevice(
        _description,
        _location,
        'uuid:abc',
      );
      expect(device, isNotNull);
      expect(device!.name, '客厅电视');
      expect(device.controlUrl, 'http://192.168.0.5:8080/AVTransport/control');
      expect(device.address, '192.168.0.5:8080');
      expect(device.id, 'uuid:abc');
    });

    test('returns null without an AVTransport service', () {
      const xml =
          '<root><device><friendlyName>X</friendlyName><serviceList>'
          '<service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1'
          '</serviceType><controlURL>/rc</controlURL></service>'
          '</serviceList></device></root>';
      expect(DlnaCastServiceImpl.parseDevice(xml, _location, 'id'), isNull);
    });

    test('keeps an absolute control URL', () {
      const xml =
          '<root><device><friendlyName>X</friendlyName><serviceList>'
          '<service><serviceType>urn:schemas-upnp-org:service:AVTransport:1'
          '</serviceType><controlURL>http://other:9000/ctrl</controlURL>'
          '</service></serviceList></device></root>';
      final device = DlnaCastServiceImpl.parseDevice(xml, _location, 'id');
      expect(device!.controlUrl, 'http://other:9000/ctrl');
    });

    test('unescapes XML entities in the friendly name', () {
      const xml =
          '<root><device><friendlyName>Tom &amp; Jerry</friendlyName>'
          '<serviceList><service>'
          '<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>'
          '<controlURL>/ctrl</controlURL></service></serviceList></device></root>';
      final device = DlnaCastServiceImpl.parseDevice(xml, _location, 'id');
      expect(device!.name, 'Tom & Jerry');
    });
  });

  group('discover', () {
    test('builds devices from SSDP responses', () async {
      final transport = FakeDlnaTransport()
        ..responses = <Map<String, String>>[
          <String, String>{'location': _location, 'usn': 'uuid:abc'},
        ]
        ..descriptions = <String, String>{_location: _description};
      final service = DlnaCastServiceImpl(transport: transport);

      final devices = await service.discover();

      expect(devices, hasLength(1));
      expect(devices.single.name, '客厅电视');
      expect(transport.gets, <String>[_location]);
    });

    test('de-duplicates repeated USNs', () async {
      final transport = FakeDlnaTransport()
        ..responses = <Map<String, String>>[
          <String, String>{'location': _location, 'usn': 'uuid:abc'},
          <String, String>{'location': _location, 'usn': 'uuid:abc'},
        ]
        ..descriptions = <String, String>{_location: _description};
      final service = DlnaCastServiceImpl(transport: transport);

      expect(await service.discover(), hasLength(1));
    });

    test('skips a renderer whose description fails', () async {
      final transport = FakeDlnaTransport()
        ..responses = <Map<String, String>>[
          <String, String>{
            'location': 'http://bad/desc.xml',
            'usn': 'uuid:bad',
          },
          <String, String>{'location': _location, 'usn': 'uuid:abc'},
        ]
        ..descriptions = <String, String>{_location: _description};
      final service = DlnaCastServiceImpl(transport: transport);

      final devices = await service.discover();
      expect(devices, hasLength(1));
      expect(devices.single.id, 'uuid:abc');
    });

    test('an empty scan yields no devices', () async {
      final service = DlnaCastServiceImpl(transport: FakeDlnaTransport());
      expect(await service.discover(), isEmpty);
    });
  });

  group('AVTransport actions', () {
    test('cast posts SetAVTransportURI then Play', () async {
      final transport = FakeDlnaTransport();
      final service = DlnaCastServiceImpl(transport: transport);

      await service.cast(_device(), 'http://x/v?api_key=t', title: '测试');

      expect(transport.posts, hasLength(2));
      expect(transport.posts[0].action, 'SetAVTransportURI');
      expect(transport.posts[0].url, _device().controlUrl);
      expect(transport.posts[0].body, contains('CurrentURI'));
      expect(transport.posts[0].body, contains('http://x/v?api_key=t'));
      expect(transport.posts[0].body, contains('测试'));
      expect(transport.posts[1].action, 'Play');
      expect(transport.posts[1].body, contains('<Speed>1</Speed>'));
    });

    test('cast XML-escapes an ampersand in the URL', () async {
      final transport = FakeDlnaTransport();
      final service = DlnaCastServiceImpl(transport: transport);

      await service.cast(_device(), 'http://x/v?a=1&b=2');

      expect(transport.posts[0].body, contains('a=1&amp;b=2'));
      expect(transport.posts[0].body, isNot(contains('a=1&b=2')));
    });

    test('stop, pause and play post their own actions', () async {
      final transport = FakeDlnaTransport();
      final service = DlnaCastServiceImpl(transport: transport);

      await service.stop(_device());
      await service.pause(_device());
      await service.play(_device());

      expect(transport.posts.map((p) => p.action).toList(), <String>[
        'Stop',
        'Pause',
        'Play',
      ]);
      expect(transport.posts[0].body, contains('<InstanceID>0</InstanceID>'));
    });
  });
}
