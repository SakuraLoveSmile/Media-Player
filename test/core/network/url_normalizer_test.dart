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
      expect(UrlNormalizer.normalize('http://host:80'), 'http://host');
    });
  });

  group('UrlNormalizer.candidates', () {
    test('adds a /emby candidate', () {
      expect(UrlNormalizer.candidates('192.168.1.10:8096'), <String>[
        'http://192.168.1.10:8096',
        'http://192.168.1.10:8096/emby',
      ]);
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

  group('UrlNormalizer.normalizeWan', () {
    test('upgrades a legacy http WAN and its percent-encoded host', () {
      expect(
        UrlNormalizer.normalizeWan(
          'http://media.%E4%B8%8A%E6%9D%89%E4%B9%9D%E6%9C%88.cn',
        ),
        'https://media.xn--fhqths51enha.cn',
      );
    });

    test('defaults a scheme-less public host to https', () {
      expect(
        UrlNormalizer.normalizeWan('media.上杉九月.cn'),
        'https://media.xn--fhqths51enha.cn',
      );
    });

    test('keeps a path and drops a trailing slash', () {
      expect(
        UrlNormalizer.normalizeWan('media.example.com/emby/'),
        'https://media.example.com/emby',
      );
    });

    test('invalid input stays null', () {
      expect(UrlNormalizer.normalizeWan('ftp://host'), isNull);
      expect(UrlNormalizer.normalizeWan('not a url'), isNull);
    });
  });

  group('UrlNormalizer.normalize IDN hosts', () {
    test('converts a Chinese host to punycode', () {
      expect(
        UrlNormalizer.normalize('https://media.上杉九月.cn'),
        'https://media.xn--fhqths51enha.cn',
      );
    });

    test('converts a Chinese host and keeps the port/sub-path', () {
      expect(
        UrlNormalizer.normalize('https://media.上杉九月.cn:443/emby/'),
        'https://media.xn--fhqths51enha.cn/emby',
      );
    });

    test('accepts a schemeless Chinese host', () {
      expect(
        UrlNormalizer.normalize('media.上杉九月.cn'),
        'http://media.xn--fhqths51enha.cn',
      );
    });

    test('tolerates full-width dots typed by an IME', () {
      expect(
        UrlNormalizer.normalize('https://media。上杉九月。cn'),
        'https://media.xn--fhqths51enha.cn',
      );
    });

    test('probe candidates use the punycode host', () {
      expect(UrlNormalizer.candidates('https://media.上杉九月.cn'), <String>[
        'https://media.xn--fhqths51enha.cn',
        'https://media.xn--fhqths51enha.cn/emby',
      ]);
    });
  });

  group('UrlNormalizer.display', () {
    test('renders a punycode host as Unicode', () {
      expect(
        UrlNormalizer.display('https://media.xn--fhqths51enha.cn'),
        'https://media.上杉九月.cn',
      );
    });

    test('keeps port and sub-path while decoding the host', () {
      expect(
        UrlNormalizer.display('https://media.xn--fhqths51enha.cn:8443/emby'),
        'https://media.上杉九月.cn:8443/emby',
      );
    });

    test('accepts a Chinese domain as input too', () {
      expect(
        UrlNormalizer.display('media.上杉九月.cn:9096'),
        'http://media.上杉九月.cn:9096',
      );
    });

    test('leaves ASCII addresses alone', () {
      expect(
        UrlNormalizer.display('http://192.168.1.10:8096/emby'),
        'http://192.168.1.10:8096/emby',
      );
      expect(
        UrlNormalizer.display('https://emby.example.com'),
        'https://emby.example.com',
      );
    });

    test('returns unusable input trimmed and unchanged', () {
      expect(UrlNormalizer.display(''), '');
      expect(UrlNormalizer.display('not a url'), 'not a url');
      expect(UrlNormalizer.display('  ftp://host  '), 'ftp://host');
    });

    test('round-trips the stored form back to the typed domain', () {
      const typed = 'https://media.上杉九月.cn';
      final String? stored = UrlNormalizer.normalize(typed);
      expect(stored, 'https://media.xn--fhqths51enha.cn');
      expect(UrlNormalizer.display(stored!), typed);
    });
  });
}
