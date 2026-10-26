import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sembast/sembast.dart';

import 'db_factory.dart';
import 'defaults.dart';
import 'models.dart';

bool _isLegacyOpenCodeZenUrl(String baseUrl) {
  final uri = Uri.tryParse(baseUrl.trim());
  if (uri == null || !uri.host.contains('opencode.ai')) return false;
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  return path == '/zen/v1';
}

class AppDatabase {
  AppDatabase(this.db);

  final Database db;

  final _providers = stringMapStoreFactory.store('providers');
  final _conversations = stringMapStoreFactory.store('conversations');
  final _messages = stringMapStoreFactory.store('messages');
  final _memories = stringMapStoreFactory.store('memories');
  final _meta = stringMapStoreFactory.store('meta');
  final _mcpServers = stringMapStoreFactory.store('mcp_servers');

  static Future<AppDatabase> open() async {
    final raw = await openDatabaseForPlatform();
    return AppDatabase(raw);
  }

  Future<void> seedProvidersIfNeeded() async {
    final count = await _providers.count(db);
    if (count > 0) return;
    for (final provider in buildDefaultProviders()) {
      await _providers.record(provider.id).put(db, provider.toJson());
    }
  }

  Future<List<ProviderConfig>> loadProviders() async {
    final defaults = buildDefaultProviders();
    final records = await _providers.find(db, finder: Finder(sortOrders: [SortOrder('sortOrder')]));
    final loaded = <String, ProviderConfig>{};
    for (final record in records) {
      final map = record.value;
      loaded[record.key] = ProviderConfig.fromJson(map);
    }
    // Add providers introduced by a new app version, and fill in missing
    // curated fallback models without clobbering user edits.
    for (final fallback in defaults) {
      final existing = loaded[fallback.id];
      if (existing == null) {
        loaded[fallback.id] = fallback;
        await _providers.record(fallback.id).put(db, fallback.toJson());
        continue;
      }
      if (!fallback.builtin || existing.demo) continue;
      // OpenCode Go used to be configured against the Zen pay-as-you-go
      // endpoint. Migrate that exact preset to the Go subscription endpoint;
      // otherwise a valid Go key is billed against the (often empty) Zen
      // balance and returns 402 "Insufficient account funds".
      if (fallback.id == 'opencode' &&
          existing.builtin &&
          _isLegacyOpenCodeZenUrl(existing.baseUrl)) {
        existing.baseUrl = fallback.baseUrl;
        existing.name = 'OpenCode Go';
        existing.description = fallback.description;
        existing.docsUrl = fallback.docsUrl;
        existing.models = List<ModelInfo>.from(fallback.models);
        existing.modelsSyncedAt = null;
        existing.syncError = null;
        await _providers.record(existing.id).put(db, existing.toJson());
      }
      final ids = existing.models.map((m) => m.id).toSet();
      final missing = fallback.models.where((m) => !ids.contains(m.id)).toList();
      if (missing.isNotEmpty) {
        existing.models = [...existing.models, ...missing];
        await _providers.record(existing.id).put(db, existing.toJson());
      }
    }
    final list = loaded.values.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  Future<void> saveProvider(ProviderConfig provider) async {
    await _providers.record(provider.id).put(db, provider.toJson());
  }

  Future<void> deleteProvider(String id) async {
    await _providers.record(id).delete(db);
  }

  Future<List<Conversation>> loadConversations() async {
    final records = await _conversations.find(
      db,
      finder: Finder(
        filter: Filter.equals('archived', false),
        sortOrders: [SortOrder('pinned', false), SortOrder('updatedAt', false)],
      ),
    );
    return records.map((r) => Conversation.fromJson(r.value)).toList();
  }

  Future<void> saveConversation(Conversation conversation) async {
    await _conversations.record(conversation.id).put(db, conversation.toJson());
  }

  Future<void> deleteConversation(String id) async {
    await _conversations.record(id).delete(db);
    final messages = await _messages.find(
      db,
      finder: Finder(filter: Filter.equals('conversationId', id)),
    );
    for (final message in messages) {
      await _messages.record(message.key).delete(db);
    }
  }

  Future<void> clearConversations() async {
    await _messages.delete(db);
    await _conversations.delete(db);
  }

  Future<List<ChatMessage>> loadMessages(String conversationId) async {
    final records = await _messages.find(
      db,
      finder: Finder(
        filter: Filter.equals('conversationId', conversationId),
        sortOrders: [SortOrder('createdAt')],
      ),
    );
    return records.map((r) => ChatMessage.fromJson(r.value)).toList();
  }

  Future<void> saveMessage(ChatMessage message) async {
    await _messages.record(message.id).put(db, message.toJson());
  }

  Future<void> deleteMessage(String id) async {
    await _messages.record(id).delete(db);
  }

  Future<UserProfile> loadProfile() async {
    final value = await _meta.record('profile').get(db);
    if (value == null) return UserProfile();
    return UserProfile.fromJson(value);
  }

  Future<void> saveProfile(UserProfile profile) async {
    await _meta.record('profile').put(db, profile.toJson());
  }

  Future<List<MemoryItem>> loadMemories() async {
    final records = await _memories.find(
      db,
      finder: Finder(sortOrders: [SortOrder('createdAt', false)]),
    );
    return records.map((r) => MemoryItem.fromJson(r.value)).toList();
  }

  Future<void> saveMemory(MemoryItem memory) async {
    await _memories.record(memory.id).put(db, memory.toJson());
  }

  Future<void> deleteMemory(String id) async {
    await _memories.record(id).delete(db);
  }

  Future<void> clearMemories() async {
    await _memories.delete(db);
  }

  Future<List<McpServerConfig>> loadMcpServers() async {
    final records = await _mcpServers.find(db);
    return records.map((r) => McpServerConfig.fromJson(r.value)).toList();
  }

  Future<void> saveMcpServer(McpServerConfig server) async {
    await _mcpServers.record(server.id).put(db, server.toJson());
  }

  Future<void> deleteMcpServer(String id) async {
    await _mcpServers.record(id).delete(db);
  }

  Future<AppSettings> loadSettings() async {
    final value = await _meta.record('settings').get(db);
    if (value == null) return AppSettings();
    return AppSettings.fromJson(value);
  }

  Future<void> saveSettings(AppSettings settings) async {
    await _meta.record('settings').put(db, settings.toJson());
  }

  Future<Map<String, dynamic>> exportAll() async {
    Future<List<Map<String, dynamic>>> dump(StoreRef<String, Map<String, Object?>> store) async {
      final records = await store.find(db);
      return records
          .map((r) => <String, dynamic>{'id': r.key, 'value': r.value})
          .toList(growable: false);
    }

    final settings = await loadSettings();
    final profile = await loadProfile();
    return {
      'app': 'Lumen',
      'exportedAt': nowUtc().toIso8601String(),
      'settings': settings.toJson(),
      'profile': profile.toJson(),
      'providers': await dump(_providers),
      'conversations': await dump(_conversations),
      'messages': await dump(_messages),
      'memories': await dump(_memories),
      'mcpServers': await dump(_mcpServers),
    };
  }

  Future<String> exportJson({bool pretty = true}) async {
    final data = await exportAll();
    return pretty ? const JsonEncoder.withIndent('  ').convert(data) : jsonEncode(data);
  }

  Future<void> close() => db.close();
}

/// API keys never enter the document database. On Android they live in
/// Keystore-backed secure storage; the web build falls back to localStorage so
/// the browser preview remains usable.
class SecretStore {
  SecretStore();

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  SharedPreferences? _prefs;
  static const _prefix = 'lumen.secret.';

  Future<SharedPreferences> _preferences() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<String?> read(String key) async {
    try {
      final value = await _secure.read(key: key);
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {
      // Fall through to the local fallback.
    }
    if (!kIsWeb) return null;
    try {
      return (await _preferences()).getString('$_prefix$key');
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
      return;
    } catch (_) {
      // Fall through.
    }
    await (await _preferences()).setString('$_prefix$key', value);
  }

  Future<void> delete(String key) async {
    try {
      await _secure.delete(key: key);
    } catch (_) {
      // Ignore.
    }
    try {
      await (await _preferences()).remove('$_prefix$key');
    } catch (_) {
      // Ignore.
    }
  }

  Future<bool> has(String key) async => (await read(key))?.isNotEmpty ?? false;
}

class AppRepository {
  AppRepository(this.db, this.secrets);

  final AppDatabase db;
  final SecretStore secrets;

  static const _providerKeyPrefix = 'provider.';

  Future<void> initialize() async {
    await db.seedProvidersIfNeeded();
  }

  Future<List<ProviderConfig>> loadProviders() async {
    final providers = await db.loadProviders();
    final result = <ProviderConfig>[];
    for (final provider in providers) {
      if (provider.demo) {
        result.add(provider.copyWith(hasKey: true));
        continue;
      }
      final key = await secrets.read('$_providerKeyPrefix${provider.id}');
      result.add(provider.copyWith(hasKey: key != null && key.isNotEmpty));
    }
    return result;
  }

  Future<String?> apiKeyFor(String providerId) =>
      secrets.read('$_providerKeyPrefix$providerId');

  Future<void> saveProvider(ProviderConfig provider, {String? apiKey, bool clearKey = false}) async {
    if (clearKey) {
      await secrets.delete('$_providerKeyPrefix${provider.id}');
      provider.hasKey = false;
    } else if (apiKey != null && apiKey.isNotEmpty) {
      await secrets.write('$_providerKeyPrefix${provider.id}', apiKey);
      provider.hasKey = true;
    }
    await db.saveProvider(provider);
  }

  Future<void> deleteProvider(ProviderConfig provider) async {
    await secrets.delete('$_providerKeyPrefix${provider.id}');
    await db.deleteProvider(provider.id);
  }

  Future<String> searchKey(SearchProvider provider) async {
    final key = switch (provider) {
      SearchProvider.tavily => 'search.tavily',
      SearchProvider.google => 'search.google',
      SearchProvider.bing => 'search.bing',
      _ => '',
    };
    if (key.isEmpty) return '';
    return await secrets.read(key) ?? '';
  }

  Future<void> setSearchKey(SearchProvider provider, String value) async {
    final key = switch (provider) {
      SearchProvider.tavily => 'search.tavily',
      SearchProvider.google => 'search.google',
      SearchProvider.bing => 'search.bing',
      _ => '',
    };
    if (key.isEmpty) return;
    if (value.trim().isEmpty) {
      await secrets.delete(key);
    } else {
      await secrets.write(key, value.trim());
    }
  }
}
