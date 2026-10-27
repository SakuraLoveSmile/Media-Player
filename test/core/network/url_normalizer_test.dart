import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/network/url_normalizer.dart';

void main() {
  group('UrlNormalizer.normalize', () {
    const cases = <String, String?>{
      'http://192.168.1.10:8096': 'http://192.168.1.10:8096',
      '192.168.1.10:8096': 'http://192.168.1.10:8096',
      '  http://192.168.1.10:8096/  ': 'http://192.168.1.10:8096',
      'https://emby.example.com/': 'https://emby.example.com',
      'https://emby.example.com/emby/': 'https://emby.example.com/emby',
      'HTTP://NAS.LOCAL:8096': 'http://nas.local:8096',
      'https://[::1]:8920/': 'https://[::1]:8920',
      'http://host/path/?api_key=abc#frag': 'http://host/path',
      'http://user:pass@host:8096': 'http://host:8096',
      'ftp://host': null,
      'file:///tmp/x': null,
      'http://': null,
      'http://host with space': null,
      '': null,
      '   ': null,
      'not a url': null,
    };

    cases.forEach((input, expected) {
      test('"$input" -> $expected', () {
        expect(UrlNormalizer.normalize(input), expected);
      });
    });

    test('keeps a non-default port', () {
      expect(
        UrlNormalizer.normalize('https://emby.example.com:8443'),
        'https://emby.example.com:8443',
      );
    });

    test('drops the scheme-default port', () {
      expect(
        UrlNormalizer.normalize('http://host:80'),
        'http://host',
      );
    });
  });

  group('UrlNormalizer.candidates', () {
    test('adds a /emby candidate', () {
      expect(
        UrlNormalizer.candidates('192.168.1.10:8096'),
        <String>['http://192.168.1.10:8096', 'http://192.168.1.10:8096/emby'],
      );
    });

    test('does not duplicate /emby', () {
      expect(
        UrlNormalizer.candidates('https://emby.example.com/emby/'),
        <String>['https://emby.example.com/emby'],
      );
    });

    test('sub-path hosts still get one /emby candidate', () {
      expect(
        UrlNormalizer.candidates('https://proxy.example.com/media'),
        <String>[
          'https://proxy.example.com/media',
          'https://proxy.example.com/media/emby',
        ],
      );
    });

    test('invalid input yields no candidates', () {
      expect(UrlNormalizer.candidates('ftp://host'), isEmpty);
    });
  });
}
