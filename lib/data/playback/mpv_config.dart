import 'dart:convert';

/// Quality settings deliberately expose a small, path-free subset of mpv.
/// No scripts, profiles, includes, stream URLs or application-owned options
/// can pass this parser. Values are checked before storage and again on use.
enum MpvQualityPreset {
  standard('默认'),
  cinema('影视'),
  animation('动画');

  const MpvQualityPreset(this.label);
  final String label;

  static MpvQualityPreset fromName(String? value) => values.firstWhere(
    (preset) => preset.name == value,
    orElse: () => standard,
  );
}

class MpvConfigIssue {
  const MpvConfigIssue(this.line, this.message);
  final int line;
  final String message;
  @override
  String toString() => '第 $line 行：$message';
}

class MpvConfigResult {
  const MpvConfigResult(this.properties, this.issues);
  final Map<String, String> properties;
  final List<MpvConfigIssue> issues;
  bool get isValid => issues.isEmpty;
}

abstract final class MpvConfig {
  static const int maxLength = 16384;

  /// Complete reset values, including all keys accepted by [parse]. Applying
  /// this map on each open prevents a previous preset from leaving options.
  static const Map<String, String> defaults = <String, String>{
    'scale': 'bilinear',
    'cscale': 'bilinear',
    'dscale': '',
    'scale-antiring': '0',
    'cscale-antiring': '0',
    'sigmoid-upscaling': 'no',
    'correct-downscaling': 'no',
    'linear-downscaling': 'no',
    'deband-iterations': '1',
    'deband-threshold': '32',
    'deband-range': '16',
    'deband-grain': '48',
    'brightness': '0',
    'contrast': '0',
    'saturation': '0',
    'gamma': '0',
    'hue': '0',
    'dither-depth': 'no',
  };

  static const Set<String> _scalers = <String>{
    'bilinear',
    'bicubic',
    'lanczos',
    'spline36',
    'spline64',
    'ewa_lanczos',
    'ewa_lanczossharp',
    'mitchell',
  };
  static const Set<String> _booleans = <String>{
    'sigmoid-upscaling',
    'correct-downscaling',
    'linear-downscaling',
  };

  static Map<String, String> preset(MpvQualityPreset preset) =>
      <String, String>{
        ...defaults,
        if (preset != MpvQualityPreset.standard) ...<String, String>{
          'scale': 'ewa_lanczossharp',
          'cscale': 'spline36',
          'dscale': 'mitchell',
          'scale-antiring': '0.7',
          'cscale-antiring': '0.7',
          'correct-downscaling': 'yes',
          'linear-downscaling': 'yes',
        },
        if (preset == MpvQualityPreset.animation) ...<String, String>{
          'sigmoid-upscaling': 'yes',
          'deband-iterations': '2',
          'deband-threshold': '32',
          'deband-range': '16',
          'deband-grain': '16',
        },
      };

  static MpvConfigResult parse(String source) {
    final properties = <String, String>{};
    final issues = <MpvConfigIssue>[];
    if (source.length > maxLength || utf8.encode(source).length > maxLength) {
      return const MpvConfigResult({}, [MpvConfigIssue(1, '配置不能超过 16 KiB')]);
    }
    final lines = source.split('\n');
    for (int index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator <= 0) {
        issues.add(MpvConfigIssue(index + 1, '请使用 选项=值；只支持单行画质选项'));
        continue;
      }
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (!defaults.containsKey(key)) {
        issues.add(MpvConfigIssue(index + 1, '不允许的选项：$key'));
        continue;
      }
      if (!_validValue(key, value)) {
        issues.add(MpvConfigIssue(index + 1, '$key 的值无效或超出范围'));
        continue;
      }
      if (properties.containsKey(key)) {
        issues.add(MpvConfigIssue(index + 1, '$key 重复，请只保留一行'));
        continue;
      }
      properties[key] = value;
    }
    return MpvConfigResult(
      Map.unmodifiable(properties),
      List.unmodifiable(issues),
    );
  }

  static bool _validValue(String key, String value) {
    if (key == 'dscale' && value.isEmpty) return true;
    if (key == 'scale' || key == 'cscale' || key == 'dscale') {
      return _scalers.contains(value);
    }
    if (_booleans.contains(key)) return value == 'yes' || value == 'no';
    if (key == 'dither-depth') {
      return const <String>{
        'no',
        'auto',
        '8',
        '10',
        '12',
        '16',
      }.contains(value);
    }
    // Decimal literals only: rejects NaN, Infinity, option separators and paths.
    if (!RegExp(r'^-?(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(value)) return false;
    final number = double.tryParse(value);
    if (number == null || !number.isFinite) return false;
    if (key.endsWith('-antiring')) return number >= 0 && number <= 1;
    if (key == 'deband-iterations') {
      return number == number.roundToDouble() && number >= 1 && number <= 16;
    }
    if (key == 'deband-range') return number >= 1 && number <= 64;
    if (key == 'deband-threshold' || key == 'deband-grain') {
      return number >= 0 && number <= 4096;
    }
    return number >= -100 && number <= 100;
  }

  static Map<String, String> resolve(MpvQualityPreset selected, String source) {
    final parsed = parse(source);
    if (!parsed.isValid) {
      throw FormatException(
        parsed.issues.map((issue) => issue.toString()).join('\n'),
      );
    }
    return <String, String>{...preset(selected), ...parsed.properties};
  }

  static String aiPrompt(String source) =>
      '''请仅修改下方 MediaPlayer 的画质配置，返回完整文本。
格式为每行 key=value；空行和以 # 开头的注释可保留。不支持 profile 或脚本。
允许的选项及默认值：
${defaults.entries.map((entry) => '${entry.key}=${entry.value}').join('\n')}
dscale 留空表示沿用 scale。scale/cscale/dscale 可选：${_scalers.join('、')}。
布尔值只能是 yes/no。antiring 范围 0～1；deband-iterations 为 1～16 整数；
deband-range 为 1～64；deband-threshold/grain 为 0～4096；brightness/contrast/saturation/gamma/hue 为 -100～100；
dither-depth 只能是 no/auto/8/10/12/16。不要添加外部文件、路径、网络或播放控制选项。
当前自定义配置（覆盖选中的内置预设；空内容表示仅使用预设）：
$source''';
}
