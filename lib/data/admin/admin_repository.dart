import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../auth/api_session.dart';
import '../models/admin_info.dart';
import '../models/json_read.dart';
import 'admin_service.dart';

/// Read-only Emby admin queries (S24).
///
/// Every request is derived from the session's resolved endpoint, exactly like
/// [LibraryRepository], so LAN and WAN URLs cannot mix. `GET /Users` and
/// `GET /Sessions` answer with bare arrays; [EmbyHttpClient] normalises them
/// into the `Items` envelope, so both parse through `Items` here.
class AdminRepository implements AdminService {
  AdminRepository(this._session);

  final ApiSession _session;

  @override
  Future<bool> isAdmin() async {
    final String? id = _session.userId;
    // Logged out (or endpoint unresolved): nobody is an admin. Returning
    // false instead of throwing keeps the settings entry simply hidden.
    if (id == null || id.isEmpty || _session.endpoint == null) return false;
    final Map<String, dynamic> json = await _session.authorizedGet(
      _uri('/Users/$id'),
    );
    return asBool(asMap(json['Policy'])['IsAdministrator']);
  }

  @override
  Future<AdminSystemInfo> systemInfo() async {
    final Map<String, dynamic> json = await _session.authorizedGet(
      _uri('/System/Info'),
    );
    return AdminSystemInfo.fromJson(json);
  }

  @override
  Future<List<AdminUser>> users() async {
    final Map<String, dynamic> json = await _session.authorizedGet(
      _uri('/Users'),
    );
    return asMapList(json['Items'])
        .map(AdminUser.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<AdminSessionInfo>> sessions() async {
    final Map<String, dynamic> json = await _session.authorizedGet(
      _uri('/Sessions'),
    );
    return asMapList(json['Items'])
        .map(AdminSessionInfo.fromJson)
        .toList(growable: false);
  }

  Uri _uri(String path) {
    final endpoint = _session.endpoint;
    if (endpoint == null) {
      throw EmbyException(AppErrorCode.unauthorized);
    }
    return endpoint.resolve(path);
  }
}
