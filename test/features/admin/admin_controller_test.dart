import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/models/admin_info.dart';
import 'package:media_player/features/admin/admin_controller.dart';

import '../../support/fake_admin_service.dart';

void main() {
  late FakeAdminService service;
  late AdminController controller;

  setUp(() {
    service = FakeAdminService(
      userList: <AdminUser>[
        const AdminUser(id: 'u-1', name: 'alice', isAdministrator: true),
        const AdminUser(id: 'u-2', name: 'bob'),
      ],
      sessionList: <AdminSessionInfo>[
        const AdminSessionInfo(
          userName: 'alice',
          client: 'Yamby',
          deviceName: 'Pixel 9',
          nowPlayingName: 'Dune',
          positionTicks: 600000000,
        ),
      ],
    );
    controller = AdminController(service);
  });

  tearDown(() => controller.dispose());

  test('load populates system info, users and sessions for an admin', () async {
    await controller.load();

    final state = controller.state;
    expect(state.loading, isFalse);
    expect(state.loaded, isTrue);
    expect(state.forbidden, isFalse);
    expect(state.error, isNull);
    expect(state.systemInfo?.serverName, 'Home');
    expect(state.systemInfo?.version, '4.10.1.0');
    expect(state.users, hasLength(2));
    expect(state.sessions.single.nowPlayingName, 'Dune');
    expect(service.isAdminCalls, 1);
    expect(service.systemInfoCalls, 1);
    expect(service.usersCalls, 1);
    expect(service.sessionsCalls, 1);
  });

  test(
    'a non-admin session is forbidden and no admin data is requested',
    () async {
      service.admin = false;

      await controller.load();

      final state = controller.state;
      expect(state.forbidden, isTrue);
      expect(state.loaded, isTrue);
      expect(state.loading, isFalse);
      expect(state.systemInfo, isNull);
      expect(state.users, isEmpty);
      expect(state.sessions, isEmpty);
      expect(service.isAdminCalls, 1);
      expect(service.systemInfoCalls, 0);
      expect(service.usersCalls, 0);
      expect(service.sessionsCalls, 0);
    },
  );

  test(
    'a refresh re-checks the gate, so a demoted account loses access',
    () async {
      await controller.load();
      expect(controller.state.forbidden, isFalse);

      service.admin = false;
      await controller.load();

      expect(controller.state.forbidden, isTrue);
      expect(controller.state.systemInfo, isNull);
      expect(controller.state.users, isEmpty);
      expect(service.isAdminCalls, 2);
      // The second load must not fetch data again.
      expect(service.systemInfoCalls, 1);
    },
  );

  test('an EmbyException maps to user-facing copy', () async {
    service.failure = EmbyException(AppErrorCode.networkUnreachable);

    await controller.load();

    final state = controller.state;
    expect(state.error, '无法连接服务器，请检查网络');
    expect(state.loaded, isTrue);
    expect(state.loading, isFalse);
    expect(state.forbidden, isFalse);
  });

  test('a forbidden failure maps to the permission message', () async {
    service.failure = EmbyException(AppErrorCode.forbidden);

    await controller.load();

    expect(controller.state.error, '没有管理员权限');
  });

  test('an unexpected failure maps to the generic message', () async {
    service.failure = EmbyException(AppErrorCode.serverError);

    await controller.load();

    expect(controller.state.error, '加载失败，请稍后重试');
  });

  test('retry after a failure loads the data', () async {
    service.failure = EmbyException(AppErrorCode.serverError);
    await controller.load();
    expect(controller.state.error, isNotNull);

    service.failure = null;
    await controller.load();

    expect(controller.state.error, isNull);
    expect(controller.state.systemInfo?.serverName, 'Home');
    expect(controller.state.users, hasLength(2));
  });

  test('a stale answer never overwrites a newer load', () async {
    // The first load is still in flight when a second one starts; the fake
    // answers synchronously, so force the ordering with a gated subclass.
    final gated = _GatedAdminService();
    final gatedController = AdminController(gated);
    addTearDown(gatedController.dispose);

    final first = gatedController.load();
    final second = gatedController.load();
    gated.gates[1].complete(true); // newer load: admin
    await second;
    expect(gatedController.state.systemInfo?.serverName, 'Home');

    gated.gates[0].complete(false); // older load finishes last
    await first;
    // The stale non-admin answer must not flip the page to 无权限.
    expect(gatedController.state.forbidden, isFalse);
    expect(gatedController.state.systemInfo?.serverName, 'Home');
  });
}

/// Gates every [isAdmin] answer so tests can finish loads out of order.
class _GatedAdminService extends FakeAdminService {
  final List<Completer<bool>> gates = <Completer<bool>>[];

  @override
  Future<bool> isAdmin() {
    isAdminCalls++;
    final gate = Completer<bool>();
    gates.add(gate);
    return gate.future;
  }
}
