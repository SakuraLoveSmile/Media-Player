import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/update/update_installer.dart';
import 'package:media_player/data/update/update_models.dart';
import 'package:media_player/data/update/update_service.dart';
import 'package:open_filex/open_filex.dart' show OpenResult, ResultType;

const String _sha =
    '0123456789abcdef0123456789abcdef'
    '0123456789abcdef0123456789abcdef';

AppRelease _release() {
  return AppRelease(
    version: '0.2.0',
    tagName: 'v0.2.0',
    notes: '修复若干问题',
    pageUrl: Uri.parse(
      'https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.2.0',
    ),
    publishedAt: DateTime.utc(2026, 10, 1, 12),
    assets: <ReleaseAsset>[
      ReleaseAsset(
        name: 'MediaPlayer-macos.zip',
        downloadUrl: Uri.parse('https://example.test/MediaPlayer-macos.zip'),
        sizeBytes: 2048,
        sha256: _sha,
      ),
    ],
  );
}

/// Thrown by the injected `exitProcess` so a test never kills the runner.
class _ExitSignal implements Exception {
  _ExitSignal(this.code);

  final int code;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('update_installer_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test('buildWindowsUpdaterArguments passes the script contract', () {
    final List<String> arguments = UpdateInstaller.buildWindowsUpdaterArguments(
      scriptPath: r'C:\Temp\MediaPlayer-update.ps1',
      processId: 4242,
      sourcePath: r'C:\Temp\extracted',
      targetPath: r'C:\Program Files\Media Player',
      executableName: 'media_player.exe',
      logPath: r'C:\Temp\MediaPlayer-update.log',
    );

    expect(arguments, <String>[
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      r'C:\Temp\MediaPlayer-update.ps1',
      '-ProcessId',
      '4242',
      '-SourcePath',
      r'C:\Temp\extracted',
      '-TargetPath',
      r'C:\Program Files\Media Player',
      '-ExecutableName',
      'media_player.exe',
      '-LogPath',
      r'C:\Temp\MediaPlayer-update.log',
    ]);
  });

  test('buildMacUpdaterScript swaps, relaunches and cleans up', () {
    final String script = UpdateInstaller.buildMacUpdaterScript(
      sourceAppPath: "/tmp/it's staging/Media Player.app",
      targetAppPath: '/Applications/Media Player.app',
      processId: 7331,
      extractedRootPath: '/tmp/mediaplayer-update-123',
    );

    expect(script, startsWith('#!/bin/bash'));
    expect(script, contains('APP_PID=7331'));
    expect(script, contains(r'''while kill -0 "$APP_PID" 2>/dev/null'''));
    expect(script, contains(r'''rm -rf "$TARGET_APP"'''));
    expect(script, contains(r'''/usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"'''));
    expect(
      script,
      contains(r'''/usr/bin/xattr -dr com.apple.quarantine "$TARGET_APP"'''),
    );
    expect(script, contains(r'''open "$TARGET_APP"'''));
    expect(script, contains(r'''rm -rf "$EXTRACT_ROOT"'''));
    // Apostrophes are escaped so a path with a quote cannot break out.
    expect(script, contains(r"'/tmp/it'\''s staging/Media Player.app'"));

    final int removeTarget = script.indexOf(r'rm -rf "$TARGET_APP"');
    final int copy = script.indexOf(r'/usr/bin/ditto "$SOURCE_APP"');
    final int quarantine = script.indexOf('/usr/bin/xattr -dr');
    final int relaunch = script.indexOf(r'open "$TARGET_APP"');
    final int removeExtract = script.indexOf(r'rm -rf "$EXTRACT_ROOT"');
    expect(removeTarget, lessThan(copy));
    expect(copy, lessThan(quarantine));
    expect(quarantine, lessThan(relaunch));
    expect(relaunch, lessThan(removeExtract));
  });

  group('openReleasePage', () {
    test('opens the release page through the injected opener', () async {
      final List<Uri> opened = <Uri>[];
      final UpdateInstaller installer = UpdateInstaller(
        targetOverride: UpdateTarget.unsupported,
        urlOpener: (Uri uri) async {
          opened.add(uri);
          return true;
        },
      );

      await installer.openReleasePage(_release());

      expect(opened.single, _release().pageUrl);
    });

    test('reports failures with a Chinese UpdateException', () async {
      final UpdateInstaller closed = UpdateInstaller(
        targetOverride: UpdateTarget.unsupported,
        urlOpener: (Uri uri) async => false,
      );
      await expectLater(
        closed.openReleasePage(_release()),
        throwsA(
          isA<UpdateException>().having(
            (UpdateException error) => error.message,
            'message',
            contains('无法打开浏览器'),
          ),
        ),
      );

      final UpdateInstaller broken = UpdateInstaller(
        targetOverride: UpdateTarget.unsupported,
        urlOpener: (Uri uri) async => throw StateError('no browser'),
      );
      await expectLater(
        broken.openReleasePage(_release()),
        throwsA(isA<UpdateException>()),
      );
    });

    test('unsupported installs fall back to the release page', () async {
      final List<Uri> opened = <Uri>[];
      final UpdateInstaller installer = UpdateInstaller(
        targetOverride: UpdateTarget.unsupported,
        urlOpener: (Uri uri) async {
          opened.add(uri);
          return true;
        },
      );

      await installer.installUpdate(
        File('${tmp.path}/does-not-exist.apk'),
        _release(),
      );

      expect(opened.single, _release().pageUrl);
    });
  });

  group('android', () {
    late File package;

    setUp(() async {
      package = File('${tmp.path}/MediaPlayer-android.apk');
      await package.writeAsString('apk-bytes');
    });

    test('opens the APK through the injected system opener', () async {
      final List<File> opened = <File>[];
      final UpdateInstaller installer = UpdateInstaller(
        targetOverride: UpdateTarget.android,
        androidOpener: (File file) async {
          opened.add(file);
          return OpenResult();
        },
      );

      await installer.installUpdate(package, _release());

      expect(opened.single.path, package.path);
    });

    test('maps a failed opener result to an UpdateException', () async {
      final UpdateInstaller installer = UpdateInstaller(
        targetOverride: UpdateTarget.android,
        androidOpener: (File file) async =>
            OpenResult(type: ResultType.noAppToOpen),
      );

      await expectLater(
        installer.installUpdate(package, _release()),
        throwsA(
          isA<UpdateException>().having(
            (UpdateException error) => error.message,
            'message',
            contains('无法调起系统安装器'),
          ),
        ),
      );
    });

    test(
      'maps opener exceptions and a missing package to UpdateException',
      () async {
        final UpdateInstaller throwing = UpdateInstaller(
          targetOverride: UpdateTarget.android,
          androidOpener: (File file) async => throw StateError('boom'),
        );
        await expectLater(
          throwing.installUpdate(package, _release()),
          throwsA(isA<UpdateException>()),
        );

        final UpdateInstaller installer = UpdateInstaller(
          targetOverride: UpdateTarget.android,
          androidOpener: (File file) async => OpenResult(),
        );
        await expectLater(
          installer.installUpdate(File('${tmp.path}/missing.apk'), _release()),
          throwsA(
            isA<UpdateException>().having(
              (UpdateException error) => error.message,
              'message',
              contains('安装包不存在'),
            ),
          ),
        );
      },
    );
  });

  group('windows install', () {
    test(
      'extracts the zip, writes the script and launches PowerShell',
      () async {
        final Directory payload = Directory('${tmp.path}/payload')
          ..createSync();
        await File('${payload.path}/media_player.exe').writeAsString('exe');
        await Directory('${payload.path}/data').create();
        await File('${payload.path}/data/app.so').writeAsString('library');
        final File zip = File('${tmp.path}/MediaPlayer-windows-x64.zip');
        await ZipFileEncoder().zipDirectory(payload, filename: zip.path);

        final Directory appDir = Directory('${tmp.path}/installed')
          ..createSync();
        final File executable = File('${appDir.path}/media_player.exe');
        await executable.writeAsString('old-exe');

        late String launchedExecutable;
        late List<String> launchedArguments;
        late ProcessStartMode launchedMode;
        final UpdateInstaller installer = UpdateInstaller(
          targetOverride: UpdateTarget.windows,
          executablePathOverride: executable.path,
          processStarter:
              (
                String executablePath,
                List<String> arguments, {
                ProcessStartMode mode = ProcessStartMode.normal,
              }) async {
                launchedExecutable = executablePath;
                launchedArguments = arguments;
                launchedMode = mode;
                return Process.start('true', <String>[]);
              },
          exitProcess: (int code) => throw _ExitSignal(code),
        );

        await expectLater(
          installer.installUpdate(zip, _release()),
          throwsA(isA<_ExitSignal>()),
        );

        expect(launchedExecutable, 'powershell.exe');
        expect(launchedMode, ProcessStartMode.detached);

        final String scriptPath =
            launchedArguments[launchedArguments.indexOf('-File') + 1];
        final File script = File(scriptPath);
        expect(script.existsSync(), isTrue);
        expect(scriptPath, endsWith('.ps1'));
        final String content = await script.readAsString();
        expect(content, contains('Copy-Item'));
        expect(content, contains('Start-Process'));
        expect(content, contains(r'$ProcessId'));
        expect(content, contains('Remove-Item'));

        final String extractedPath =
            launchedArguments[launchedArguments.indexOf('-SourcePath') + 1];
        expect(Directory(extractedPath).existsSync(), isTrue);
        expect(
          launchedArguments[launchedArguments.indexOf('-ProcessId') + 1],
          '$pid',
        );
        expect(
          launchedArguments[launchedArguments.indexOf('-TargetPath') + 1],
          appDir.path,
        );
        expect(
          launchedArguments[launchedArguments.indexOf('-ExecutableName') + 1],
          'media_player.exe',
        );
        expect(
          launchedArguments[launchedArguments.indexOf('-LogPath') + 1],
          endsWith('mediaplayer-update-$pid.log'),
        );

        await Directory(extractedPath).delete(recursive: true);
        await script.delete();
      },
    );
  });

  group('macOS install', () {
    test(
      'extracts with ditto, writes the bash script and launches it',
      () async {
        final Directory installDir = Directory('${tmp.path}/install')
          ..createSync();
        final Directory targetApp = Directory(
          '${installDir.path}/Media Player.app',
        )..createSync();
        await File('${targetApp.path}/old-marker.txt').writeAsString('old');
        final File executable = File(
          '${targetApp.path}/Contents/MacOS/Media Player',
        );
        await executable.parent.create(recursive: true);
        await executable.writeAsString('binary');

        final Directory sourceParent = Directory('${tmp.path}/source')
          ..createSync();
        final Directory sourceApp = Directory(
          '${sourceParent.path}/Media Player.app',
        )..createSync();
        await File('${sourceApp.path}/new-marker.txt').writeAsString('new');
        final File zip = File('${tmp.path}/MediaPlayer-macos.zip');
        final ProcessResult zipped = await Process.run('ditto', <String>[
          '-c',
          '-k',
          '--sequesterRsrc',
          '--keepParent',
          sourceApp.path,
          zip.path,
        ]);
        expect(zipped.exitCode, 0, reason: '${zipped.stderr}');

        late String launchedExecutable;
        final List<String> launchedArguments = <String>[];
        final UpdateInstaller installer = UpdateInstaller(
          targetOverride: UpdateTarget.macos,
          executablePathOverride: executable.path,
          processStarter:
              (
                String executablePath,
                List<String> arguments, {
                ProcessStartMode mode = ProcessStartMode.normal,
              }) async {
                launchedExecutable = executablePath;
                launchedArguments.addAll(arguments);
                return Process.start('true', <String>[]);
              },
          exitProcess: (int code) => throw _ExitSignal(code),
        );

        await expectLater(
          installer.installUpdate(zip, _release()),
          throwsA(isA<_ExitSignal>()),
        );

        expect(launchedArguments, isEmpty);
        expect(launchedExecutable, endsWith('.sh'));
        final File script = File(launchedExecutable);
        expect(script.existsSync(), isTrue);
        final ProcessResult executableCheck = await Process.run(
          'test',
          <String>['-x', script.path],
        );
        expect(executableCheck.exitCode, 0, reason: 'script must be chmod u+x');

        final String content = await script.readAsString();
        expect(content, contains('SOURCE_APP='));
        expect(content, contains(targetApp.path));

        final RegExpMatch? extractMatch = RegExp(r"EXTRACT_ROOT='([^']*)'")
            .firstMatch(content);
        expect(extractMatch, isNotNull);
        final Directory extracted = Directory(extractMatch!.group(1)!);
        expect(extracted.existsSync(), isTrue);

        // The real helper script removes the extraction directory after a
        // successful swap; the injected starter never runs it, so clean up.
        if (extracted.existsSync()) {
          await extracted.delete(recursive: true);
        }
        await script.delete();
      },
      skip: Platform.isMacOS ? false : 'ditto/detached launch are macOS only',
    );
  });

  group('macOS script execution', () {
    test('replaces the bundle, relaunches and removes staging', () async {
      final Directory stubDir = Directory('${tmp.path}/bin')..createSync();
      final File openLog = File('${tmp.path}/opened.txt');
      final File openStub = File('${stubDir.path}/open');
      await openStub.writeAsString(
        '#!/bin/bash\nprintf "%s" "\$1" > "${openLog.path}"\n',
      );
      await Process.run('chmod', <String>['u+x', openStub.path]);

      final Directory installDir = Directory('${tmp.path}/install')
        ..createSync();
      final Directory targetApp = Directory(
        '${installDir.path}/Media Player.app',
      )..createSync();
      await File('${targetApp.path}/old-marker.txt').writeAsString('old');
      final Directory sourceApp = Directory(
        '${tmp.path}/source/Media Player.app',
      )..createSync(recursive: true);
      await File('${sourceApp.path}/new-marker.txt').writeAsString('new');
      final Directory extractRoot = Directory('${tmp.path}/extract')
        ..createSync();

      // A PID that already exited, so the wait loop returns immediately.
      final Process dead = await Process.start('true', <String>[]);
      final int deadPid = dead.pid;
      await dead.exitCode;

      final String scriptContent = UpdateInstaller.buildMacUpdaterScript(
        sourceAppPath: sourceApp.path,
        targetAppPath: targetApp.path,
        processId: deadPid,
        extractedRootPath: extractRoot.path,
      );
      final File script = File('${tmp.path}/update.sh');
      await script.writeAsString(scriptContent);
      await Process.run('chmod', <String>['u+x', script.path]);

      final String parentPath = Platform.environment['PATH'] ?? '/usr/bin:/bin';
      final ProcessResult result = await Process.run(
        'bash',
        <String>[script.path],
        environment: <String, String>{'PATH': '${stubDir.path}:$parentPath'},
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(File('${targetApp.path}/new-marker.txt').existsSync(), isTrue);
      expect(File('${targetApp.path}/old-marker.txt').existsSync(), isFalse);
      expect(await openLog.readAsString(), targetApp.path);
      expect(extractRoot.existsSync(), isFalse);
    }, skip: Platform.isMacOS ? false : 'ditto/xattr/open are macOS only');
  });
}
