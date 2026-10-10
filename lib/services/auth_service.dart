import 'dart:convert';
import 'dart:io';

import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Finds the `keys/` directory, loads the OAuth client JSON and signs in.
class AuthService {
  static const scopes = [gcal.CalendarApi.calendarScope];
  static const _tokenFile = 'token.json';

  AutoRefreshingAuthClient? _client;

  /// `GCAL_KEYS_DIR`, else `keys/` in the working directory or a parent of the
  /// executable (walking upward), else `~/.config/gcal_access/keys`.
  static Directory? findKeysDir() {
    final env = Platform.environment['GCAL_KEYS_DIR'];
    if (env != null && Directory(env).existsSync()) return Directory(env);
    final starts = [
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];
    for (final start in starts) {
      var dir = start.absolute;
      for (var i = 0; i < 8; i++) {
        final keys = Directory('${dir.path}/keys');
        if (keys.existsSync()) return keys;
        if (dir.parent.path == dir.path) break;
        dir = dir.parent;
      }
    }
    final home = Platform.environment['HOME'];
    final config =
        Platform.environment['XDG_CONFIG_HOME'] ??
        (home == null ? null : '$home/.config');
    if (config != null && Directory('$config/gcal_access/keys').existsSync()) {
      return Directory('$config/gcal_access/keys');
    }
    return null;
  }

  ClientId _loadClientId(Directory keys) {
    final candidates =
        keys
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  f.path.toLowerCase().endsWith('.json') &&
                  !f.path.endsWith(_tokenFile),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (candidates.isEmpty) {
      throw AuthException(
        'No credentials JSON found in ${keys.path}.\n'
        'See keys/KEY.md for how to create one.',
      );
    }
    try {
      final json = jsonDecode(
        candidates.first.readAsStringSync(),
      ) as Map<String, dynamic>;
      final block = (json['installed'] ?? json['web']) as Map<String, dynamic>;
      return ClientId(
        block['client_id'] as String,
        block['client_secret'] as String?,
      );
    } catch (_) {
      throw AuthException(
        '${candidates.first.path} is not a valid Google '
        'OAuth client JSON. See keys/KEY.md for the expected format.',
      );
    }
  }

  AccessCredentials? _loadToken(File file) {
    try {
      final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return AccessCredentials(
        AccessToken(
          j['type'] as String,
          j['data'] as String,
          DateTime.parse(j['expiry'] as String).toUtc(),
        ),
        j['refreshToken'] as String?,
        (j['scopes'] as List).cast<String>(),
      );
    } catch (_) {
      return null;
    }
  }

  void _saveToken(File file, AccessCredentials c) {
    file.writeAsStringSync(
      jsonEncode({
        'type': c.accessToken.type,
        'data': c.accessToken.data,
        'expiry': c.accessToken.expiry.toIso8601String(),
        'refreshToken': c.refreshToken,
        'scopes': c.scopes,
      }),
    );
  }

  /// Returns an authenticated client, signing in via the browser if needed.
  Future<http.Client> client() async {
    if (_client != null) return _client!;
    final keys = findKeysDir();
    if (keys == null) {
      throw AuthException('keys/ directory not found. See keys/KEY.md.');
    }
    final clientId = _loadClientId(keys);
    final tokenFile = File('${keys.path}/$_tokenFile');

    final saved = tokenFile.existsSync() ? _loadToken(tokenFile) : null;
    AutoRefreshingAuthClient client;
    if (saved != null && saved.refreshToken != null) {
      client = autoRefreshingClient(clientId, saved, http.Client());
    } else {
      client = await clientViaUserConsent(clientId, scopes, (url) async {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      });
    }
    client.credentialUpdates.listen((c) => _saveToken(tokenFile, c));
    _saveToken(tokenFile, client.credentials);
    return _client = client;
  }

  void signOut() {
    _client?.close();
    _client = null;
    final keys = findKeysDir();
    if (keys != null) {
      final f = File('${keys.path}/$_tokenFile');
      if (f.existsSync()) f.deleteSync();
    }
  }
}
