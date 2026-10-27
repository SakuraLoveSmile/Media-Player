import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/device/device_info.dart';
import '../data/api/emby_http_client.dart';
import '../data/auth/auth_repository.dart';
import '../data/endpoints/endpoint_probe.dart';
import '../data/endpoints/endpoint_resolver.dart';
import '../data/storage/device_id_store.dart';
import '../data/storage/profile_store.dart';
import '../data/storage/session_store.dart';
import '../data/storage/storage_factory.dart';
import '../data/storage/token_store.dart';
import 'services.dart';

/// Builds the single app-wide service graph. Widget tests override this
/// provider so no plugin or network call happens.
final bootstrapProvider = FutureProvider<AppServices>((ref) async {
  final store = await createKeyValueStore();
  final deviceId = await DeviceIdStore(store).getOrCreate();

  final dio = Dio();
  final client = EmbyHttpClient(dio, deviceId: deviceId);
  final resolver = EndpointResolver(HttpEndpointProbe(client));
  final auth = AuthRepository(
    client: client,
    resolver: resolver,
    tokenStore: TokenStore(store),
    sessionStore: SessionStore(store),
    profileStore: ProfileStore(store),
    deviceId: deviceId,
    clientName: AppConfig.clientName,
    deviceName: defaultDeviceName(),
    appVersion: AppConfig.appVersion,
  );

  ref.onDispose(() {
    auth.dispose();
    dio.close(force: true);
  });

  return AppServices(
    auth: auth,
    client: client,
    resolver: resolver,
    deviceId: deviceId,
  );
});
