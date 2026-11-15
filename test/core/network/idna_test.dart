import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/network/idna.dart';

void main() {
  group('Idna.toAscii', () {
    // Reference values produced by Python's `idna` codec (UTS #46).
    const unicodeToPunycode = <String, String>{
      '上杉九月': 'xn--fhqths51enha',
      'münchen': 'xn--mnchen-3ya',
      '中文': 'xn--fiq228c',
      '例え': 'xn--r8jz45g',
      '测试-测试': 'xn----rq9bb4832aca',
      '中国': 'xn--fiqs8s',
      'ça': 'xn--a-5fa',
    };

    unicodeToPunycode.forEach((input, expected) {
      test('"$input" -> "$expected"', () {
        expect(Idna.toAscii(input), expected);
      });
    });

    test('converts only the non-ASCII labels', () {
      expect(
        Idna.toAscii('media.上杉九月.cn'),
        'media.xn--fhqths51enha.cn',
      );
      expect(
        Idna.toAscii('EMBY.上杉九月.CN'),
        'emby.xn--fhqths51enha.cn',
      );
    });

    test('leaves ASCII hosts untouched except lower-casing', () {
      expect(Idna.toAscii('NAS.LOCAL'), 'nas.local');
      expect(Idna.toAscii('192.168.1.10'), '192.168.1.10');
      expect(Idna.toAscii('media.xn--fhqths51enha.cn'),
          'media.xn--fhqths51enha.cn');
    });

    test('treats ideographic and full-width dots as separators', () {
      expect(Idna.toAscii('media。上杉九月。cn'), 'media.xn--fhqths51enha.cn');
      expect(Idna.toAscii('media．上杉九月．cn'), 'media.xn--fhqths51enha.cn');
      expect(Idna.toAscii('media｡上杉九月｡cn'), 'media.xn--fhqths51enha.cn');
    });

    test('folds full-width ASCII before encoding', () {
      expect(Idna.toAscii('ｍｅｄｉａ.ｃｎ'), 'media.cn');
    });

    test('keeps IPv6 literals as-is', () {
      expect(Idna.toAscii('::1'), '::1');
      expect(Idna.toAscii('fe80::1'), 'fe80::1');
    });

    test('keeps an empty host empty', () {
      expect(Idna.toAscii(''), '');
    });
  });

  group('Idna.toUnicode', () {
    test('decodes punycode labels back to Unicode', () {
      const cases = <String, String>{
        'xn--fhqths51enha': '上杉九月',
        'xn--mnchen-3ya': 'münchen',
        'xn--fiq228c': '中文',
        'xn--r8jz45g': '例え',
        'xn----rq9bb4832aca': '测试-测试',
        'xn--fiqs8s': '中国',
        'xn--a-5fa': 'ça',
      };
      cases.forEach((input, expected) {
        expect(Idna.toUnicode(input), expected);
      });
    });

    test('decodes only the xn-- labels and keeps the rest', () {
      expect(
        Idna.toUnicode('media.xn--fhqths51enha.cn'),
        'media.上杉九月.cn',
      );
      expect(Idna.toUnicode('nas.local'), 'nas.local');
      expect(Idna.toUnicode('192.168.1.10'), '192.168.1.10');
    });

    test('accepts an upper-case xn-- prefix', () {
      expect(Idna.toUnicode('XN--FHQTHS51ENHA.cn'), '上杉九月.cn');
    });

    test('leaves a malformed payload untouched', () {
      expect(Idna.toUnicode('xn--!!!.cn'), 'xn--!!!.cn');
      expect(Idna.toUnicode('xn--'), 'xn--');
    });

    test('keeps IPv6 literals as-is', () {
      expect(Idna.toUnicode('::1'), '::1');
      expect(Idna.toUnicode('fe80::1'), 'fe80::1');
    });

    test('round-trips everything toAscii can encode', () {
      const labels = <String>[
        '上杉九月',
        'münchen',
        '中文',
        '例え',
        '测试-测试',
        '中国',
        '日本',
        'ça',
      ];
      for (final label in labels) {
        expect(Idna.toUnicode(Idna.toAscii(label)), label);
      }
    });
  });
}
