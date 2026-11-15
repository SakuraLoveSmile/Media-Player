/// IDNA host conversion (contract §1.2).
///
/// Dart's [Uri] keeps a non-ASCII host percent-encoded — typing
/// `https://media.上杉九月.cn` yields host `media.%E4%B8%8A...` — which no DNS
/// resolver can look up, so the request dies with "Failed host lookup" before
/// it ever reaches the server. DNS and TLS only understand the ASCII (punycode)
/// form, so addresses are converted at the URL boundary.
///
/// This is the subset of IDNA the login form needs: full-width input mapping
/// (Chinese IMEs produce it in a URL field) plus RFC 3492 punycode per label.
/// Validation stays permissive — anything that is not a non-ASCII label is
/// passed through as before.
///
/// [toUnicode] is the inverse and exists only for text shown to the user;
/// requests and stored addresses always keep the ASCII form.
abstract final class Idna {
  // RFC 3492 §5 parameters.
  static const int _base = 36;
  static const int _tMin = 1;
  static const int _tMax = 26;
  static const int _skew = 38;
  static const int _damp = 700;
  static const int _initialBias = 72;
  static const int _initialN = 0x80;
  static const int _delimiter = 0x2D;
  static const int _maxUnicode = 0x10FFFF;

  /// The loop bound of RFC 3492's adaptation step: `(base - tMin) * tMax / 2`.
  static const int _adaptationThreshold = ((_base - _tMin) * _tMax) ~/ 2;

  /// Converts [host] to the ASCII form DNS resolves.
  ///
  /// IPv6 literals (containing `:`) are already ASCII and are returned as-is.
  /// Every other label with a non-ASCII code point becomes `xn--` + punycode.
  static String toAscii(String host) {
    if (host.isEmpty || host.contains(':')) return host;

    final parts = _mapInputVariants(host).split('.');
    final labels = <String>[];
    for (final label in parts) {
      if (label.isEmpty) {
        labels.add(label);
        continue;
      }
      if (!label.runes.any((rune) => rune > 0x7F)) {
        labels.add(label.toLowerCase());
        continue;
      }
      labels.add('xn--${_encode(label.toLowerCase())}');
    }
    return labels.join('.');
  }

  /// IDNA input mapping: ideographic/full-width dots separate labels, and
  /// full-width ASCII (U+FF01..U+FF5E) is folded to its ASCII equivalent.
  static String _mapInputVariants(String host) {
    final buffer = StringBuffer();
    for (final rune in host.runes) {
      if (rune == 0x3002 || rune == 0xFF0E || rune == 0xFF61) {
        buffer.writeCharCode(0x2E);
      } else if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// Decodes [host] back to its Unicode form for display.
  ///
  /// Only labels that start with `xn--` are decoded; a label whose punycode
  /// payload is malformed is left untouched, so unknown or hand-written hosts
  /// still render. IPv6 literals are returned as-is.
  static String toUnicode(String host) {
    if (host.isEmpty || host.contains(':')) return host;

    final labels = <String>[];
    for (final label in host.split('.')) {
      if (!label.toLowerCase().startsWith('xn--')) {
        labels.add(label);
        continue;
      }
      final decoded = _decodeLabel(label.substring(4).toLowerCase());
      labels.add(decoded ?? label);
    }
    return labels.join('.');
  }

  /// RFC 3492 §6.3 encoding of one label.
  static String _encode(String label) {
    final codePoints = label.runes.toList(growable: false);
    final output = <int>[];

    var basicCount = 0;
    for (final codePoint in codePoints) {
      if (codePoint < _initialN) {
        output.add(codePoint);
        basicCount++;
      }
    }
    var handled = basicCount;
    if (basicCount > 0) output.add(_delimiter);

    var n = _initialN;
    var delta = 0;
    var bias = _initialBias;
    while (handled < codePoints.length) {
      var next = _maxUnicode;
      for (final codePoint in codePoints) {
        if (codePoint >= n && codePoint < next) next = codePoint;
      }
      delta += (next - n) * (handled + 1);
      n = next;

      for (final codePoint in codePoints) {
        if (codePoint < n) delta++;
        if (codePoint != n) continue;

        var q = delta;
        for (var k = _base; ; k += _base) {
          final threshold = _threshold(k, bias);
          if (q < threshold) break;
          output.add(
            _digit(threshold + (q - threshold) % (_base - threshold)),
          );
          q = (q - threshold) ~/ (_base - threshold);
        }
        output.add(_digit(q));
        bias = _adapt(delta, handled + 1, handled == basicCount);
        delta = 0;
        handled++;
      }
      delta++;
      n++;
    }

    return String.fromCharCodes(output);
  }

  /// RFC 3492 §6.2 decoding of one label's punycode payload.
  ///
  /// Returns `null` when the payload is malformed, so callers can keep the
  /// original text instead of rendering garbage.
  static String? _decodeLabel(String payload) {
    final output = <int>[];

    final delimiter = payload.lastIndexOf('-');
    if (delimiter >= 0) {
      for (var index = 0; index < delimiter; index++) {
        final code = payload.codeUnitAt(index);
        if (code >= _initialN) return null;
        output.add(code);
      }
    }

    var index = delimiter < 0 ? 0 : delimiter + 1;
    var n = _initialN;
    var i = 0;
    var bias = _initialBias;

    while (index < payload.length) {
      final oldI = i;
      var weight = 1;
      for (var k = _base; ; k += _base) {
        if (index >= payload.length) return null;
        final digit = _decodeDigit(payload.codeUnitAt(index++));
        if (digit < 0) return null;
        i += digit * weight;
        final threshold = _threshold(k, bias);
        if (digit < threshold) break;
        weight *= _base - threshold;
      }
      bias = _adapt(i - oldI, output.length + 1, oldI == 0);
      n += i ~/ (output.length + 1);
      if (n > _maxUnicode || (n >= 0xD800 && n <= 0xDFFF)) return null;
      i %= output.length + 1;
      output.insert(i, n);
      i++;
    }

    if (output.isEmpty) return null;
    return String.fromCharCodes(output);
  }

  /// RFC 3492 §6.1 threshold for bias [bias] at position [k].
  static int _threshold(int k, int bias) {
    if (k <= bias) return _tMin;
    if (k >= bias + _tMax) return _tMax;
    return k - bias;
  }

  /// RFC 3492 §6.1 bias adaptation.
  static int _adapt(int delta, int numPoints, bool firstTime) {
    var value = firstTime ? delta ~/ _damp : delta ~/ 2;
    value += value ~/ numPoints;

    var k = 0;
    while (value > _adaptationThreshold) {
      value ~/= _base - _tMin;
      k += _base;
    }
    return k + (_base * value) ~/ (value + _skew);
  }

  /// 0..25 => 'a'..'z', 26..35 => '0'..'9' (RFC 3492 §6.1).
  static int _digit(int digit) =>
      digit < 26 ? 0x61 + digit : 0x30 + (digit - 26);

  /// Inverse of [_digit]; `-1` means "not a punycode digit".
  static int _decodeDigit(int codeUnit) {
    if (codeUnit >= 0x61 && codeUnit <= 0x7A) return codeUnit - 0x61;
    if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30 + 26;
    return -1;
  }
}
