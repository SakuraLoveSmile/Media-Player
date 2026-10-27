import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const SmokeApp());
}

class SmokeApp extends StatefulWidget {
  const SmokeApp({super.key});

  @override
  State<SmokeApp> createState() => _SmokeAppState();
}

class _SmokeAppState extends State<SmokeApp> {
  late final Player player;
  late final VideoController controller;
  final List<Map<String, dynamic>> results = [];
  final List<String> currentErrors = [];
  String current = 'init';

  late final bool isWindows = Platform.isWindows;
  late final String exeDir = File(Platform.resolvedExecutable).parent.path;
  late final File logFile =
      File('$exeDir${Platform.pathSeparator}m0_smoke.log');
  late final File resultFile =
      File('$exeDir${Platform.pathSeparator}m0_result.json');
  late final File configFile =
      File('$exeDir${Platform.pathSeparator}emby_config.json');

  void _log(String message) {
    final line = '${DateTime.now().toIso8601String()} $message';
    debugPrint(line);
    if (!isWindows) return;
    try {
      logFile.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    if (isWindows) {
      try {
        logFile.writeAsStringSync('');
      } catch (_) {}
    }
    player = Player();
    controller = VideoController(player);
    player.stream.position
        .listen((p) => _log('M0_POS[$current]=${p.inMilliseconds}'));
    player.stream.duration
        .listen((d) => _log('M0_DURATION[$current]=${d.inMilliseconds}'));
    player.stream.playing
        .listen((v) => _log('M0_PLAYING[$current]=$v'));
    player.stream.buffering
        .listen((b) => _log('M0_BUFFERING[$current]=$b'));
    player.stream.error.listen((e) {
      currentErrors.add(e);
      _log('M0_ERROR[$current]=$e');
    });
    _run();
  }

  List<(String, Media)> _scenariosFromConfig() {
    if (!configFile.existsSync()) return [];
    try {
      var text = configFile.readAsStringSync();
      if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
        text = text.substring(1);
      }
      final decoded = jsonDecode(text);
      final raw = decoded is Map ? decoded['items'] : null;
      final rawItems = raw is List ? raw : (raw is Map ? [raw] : null);
      if (rawItems == null) return [];
      final scenarios = <(String, Media)>[];
      for (final entry in rawItems) {
        if (entry is! Map) continue;
        final url = entry['url'] as String?;
        if (url == null || url.isEmpty) continue;
        final name = (entry['name'] as String?) ?? 'emby';
        final token = entry['token'] as String?;
        scenarios.add((
          name,
          Media(
            url,
            httpHeaders: (token != null && token.isNotEmpty)
                ? {'X-Emby-Token': token}
                : null,
          ),
        ));
      }
      _log('M0_CONFIG items=${scenarios.length}');
      return scenarios;
    } catch (e) {
      _log('M0_CONFIG_ERROR=$e');
      return [];
    }
  }

  Future<void> _run() async {
    final host = Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';
    final base = 'http://$host:8088';
    const defineUrl = String.fromEnvironment('EMBY_DIRECT_URL');
    const defineToken = String.fromEnvironment('EMBY_TOKEN');
    final embyUrl = defineUrl.isNotEmpty
        ? defineUrl
        : (Platform.environment['EMBY_DIRECT_URL'] ?? '');
    final embyToken = defineToken.isNotEmpty
        ? defineToken
        : (Platform.environment['EMBY_TOKEN'] ?? '');
    final scenarios = <(String, Media)>[];
    scenarios.addAll(_scenariosFromConfig());
    if (scenarios.isEmpty && embyUrl.isNotEmpty) {
      final uri = Uri.parse(embyUrl);
      final headerParams = Map<String, String>.from(uri.queryParameters)
        ..remove('api_key');
      final headerUrl = uri.replace(queryParameters: headerParams).toString();
      scenarios.add(('emby_direct_query', Media(embyUrl)));
      if (embyToken.isNotEmpty) {
        scenarios.add((
          'emby_direct_header',
          Media(headerUrl, httpHeaders: {'X-Emby-Token': embyToken}),
        ));
      }
    }
    if (scenarios.isEmpty && isWindows) {
      _log('M0_NO_INPUT: emby_config.json missing or empty');
      _finish();
      return;
    }
    if (scenarios.isEmpty) {
      scenarios.addAll([
        ('asset', Media('asset:///assets/test.mp4')),
        ('http_mp4', Media('$base/test.mp4')),
        (
          'http_hevc_mkv_auth',
          Media(
            '$base/protected/test_hevc.mkv',
            httpHeaders: const {'X-Test-Token': 'm0secret'},
          ),
        ),
        ('hls', Media('$base/hls/index.m3u8')),
      ]);
    }

    for (final scenario in scenarios) {
      current = scenario.$1;
      currentErrors.clear();
      if (mounted) setState(() {});
      _log('M0_SCENARIO=$current');
      final result = <String, dynamic>{'scenario': current};
      try {
        await player.open(scenario.$2, play: true);
        _log('M0_OPEN_OK[$current]');
        if (current == 'http_hevc_mkv_auth') {
          await Future<void>.delayed(const Duration(seconds: 2));
          await player.setSubtitleTrack(
            SubtitleTrack.uri('$base/subs.srt', title: 'M0 SRT'),
          );
          _log(
            'M0_SUB_SET[$current] tracks=${player.state.tracks.subtitle.length}',
          );
        }
        final waitSeconds = current == 'asset' ? 6 : 15;
        await Future<void>.delayed(Duration(seconds: waitSeconds));
        final state = player.state;
        result.addAll({
          'duration_ms': state.duration.inMilliseconds,
          'position_ms': state.position.inMilliseconds,
          'width': state.width,
          'height': state.height,
        });
        _log(
          'M0_RESULT[$current] duration=${state.duration.inMilliseconds} '
          'position=${state.position.inMilliseconds} '
          'width=${state.width} height=${state.height}',
        );
      } catch (e) {
        result['fail'] = e.toString();
        _log('M0_RESULT[$current] FAIL=$e');
      }
      result['errors'] = List<String>.from(currentErrors);
      results.add(result);
      try {
        await player.stop();
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    _log('M0_ALL_DONE');
    _finish();
  }

  void _finish() {
    if (!isWindows) return;
    try {
      resultFile.writeAsStringSync(
        JsonEncoder.withIndent('  ').convert({
          'finished_at': DateTime.now().toIso8601String(),
          'results': results,
        }),
      );
    } catch (e) {
      _log('M0_RESULT_WRITE_ERROR=$e');
    }
    Future<void>.delayed(const Duration(milliseconds: 500), () => exit(0));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Expanded(child: Video(controller: controller)),
            Text(
              'scenario: $current',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
