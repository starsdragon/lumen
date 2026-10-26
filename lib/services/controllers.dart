import 'dart:async';

import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../data/database.dart';
import '../data/defaults.dart';
import '../data/models.dart';
import 'api/model_sync.dart';
import 'mcp_client.dart';
import 'memory_transfer.dart';
import 'search_service.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this.repo);

  final AppRepository repo;
  AppSettings settings = AppSettings();
  SearchCredentials credentials = const SearchCredentials();
  bool loaded = false;

  Future<void> load() async {
    settings = await repo.db.loadSettings();
    credentials = SearchCredentials(
      tavily: await repo.searchKey(SearchProvider.tavily),
      google: await repo.searchKey(SearchProvider.google),
      bing: await repo.searchKey(SearchProvider.bing),
    );
    loaded = true;
    notifyListeners();
  }

  Future<void> update(AppSettings next) async {
    settings = next;
    notifyListeners();
    await repo.db.saveSettings(next);
  }

  Future<void> setTheme(ThemeMode mode) =>
      update(settings.copyWith(themeMode: mode));

  Future<void> setOnboardingDone(bool done) =>
      update(settings.copyWith(onboardingDone: done));

  Future<void> setSearch(SearchConfig config) =>
      update(settings.copyWith(search: config));

  Future<void> setSearchKey(SearchProvider provider, String value) async {
    await repo.setSearchKey(provider, value);
    credentials = SearchCredentials(
      tavily: await repo.searchKey(SearchProvider.tavily),
      google: await repo.searchKey(SearchProvider.google),
      bing: await repo.searchKey(SearchProvider.bing),
    );
    notifyListeners();
  }

  ModelTokenLimit? modelLimitFor(String providerId, String modelId) =>
      settings.modelLimits[modelLimitKey(providerId, modelId)];

  int inputTokensFor(ProviderConfig provider, ModelInfo model) =>
      effectiveInputLimit(model, modelLimitFor(provider.id, model.id));

  int outputTokensFor(ProviderConfig provider, ModelInfo model) =>
      effectiveOutputLimit(model, modelLimitFor(provider.id, model.id));

  Future<void> setModelLimit(
    String providerId,
    String modelId,
    ModelTokenLimit? limit,
  ) {
    final next = Map<String, ModelTokenLimit>.from(settings.modelLimits);
    final key = modelLimitKey(providerId, modelId);
    if (limit == null || !limit.isValid) {
      next.remove(key);
    } else {
      next[key] = limit;
    }
    return update(settings.copyWith(modelLimits: next));
  }

  Future<void> rememberSelection(String providerId, String modelId) {
    if (settings.lastUsedProviderId == providerId &&
        settings.lastUsedModelId == modelId) {
      return Future.value();
    }
    return update(
      settings.copyWith(
        lastUsedProviderId: providerId,
        lastUsedModelId: modelId,
      ),
    );
  }
}

class ModelSelection {
  const ModelSelection(this.provider, this.model);

  final ProviderConfig provider;
  final ModelInfo model;
}

/// Merge a fresh `/models` response with local manual entries. Manual entries
/// win on ID collisions; curated/previous windows win only when larger.
List<ModelInfo> mergeSyncedModels({
  required List<ModelInfo> synced,
  required List<ModelInfo> current,
}) {
  final previous = {for (final model in current) model.id: model};
  final manual = {
    for (final model in current)
      if (model.source == 'manual') model.id: model,
  };
  final merged = <ModelInfo>[];
  for (final model in synced) {
    final manualModel = manual.remove(model.id);
    if (manualModel != null) {
      merged.add(manualModel);
      continue;
    }
    final old = previous[model.id];
    merged.add(
      old != null && old.contextWindow > model.contextWindow
          ? model.copyWith(contextWindow: old.contextWindow)
          : model,
    );
  }
  merged.addAll(manual.values);
  return merged;
}

class ProvidersController extends ChangeNotifier {
  ProvidersController(this.repo);

  final AppRepository repo;
  final ModelSyncService _sync = ModelSyncService();
  List<ProviderConfig> providers = [];
  bool loading = true;
  final Set<String> syncing = {};

  Future<void> load() async {
    providers = await repo.loadProviders();
    loading = false;
    notifyListeners();
    unawaited(_autoSync());
  }

  Future<void> _autoSync() async {
    for (final provider in List<ProviderConfig>.from(providers)) {
      if (provider.demo || !provider.enabled || !provider.hasKey) continue;
      final last = provider.modelsSyncedAt;
      if (last != null && DateTime.now().difference(last).inHours < 12) continue;
      try {
        await refreshModels(provider, silent: true);
      } catch (_) {
        // The sync error is stored on the provider; keep starting up.
      }
    }
  }

  ProviderConfig? byId(String id) {
    for (final provider in providers) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  ModelInfo? modelOf(String providerId, String modelId) {
    final provider = byId(providerId);
    if (provider == null) return null;
    for (final model in provider.models) {
      if (model.id == modelId) return model;
    }
    return null;
  }

  List<ProviderConfig> get readyProviders =>
      providers.where((p) => p.ready).toList(growable: false);

  ModelSelection resolve(String providerId, String modelId, {bool imageMode = false}) {
    var provider = byId(providerId);
    if (provider == null || !provider.ready) {
      provider = readyProviders.firstOrNull ?? byId('demo');
    }
    provider ??= buildDefaultProviders().first;
    final pool = imageMode ? provider.imageModels : provider.chatModels;
    ModelInfo? model;
    for (final item in pool) {
      if (item.id == modelId) {
        model = item;
        break;
      }
    }
    if (model == null && pool.isNotEmpty) {
      if (provider.id == 'opencode') {
        const preferred = [
          'glm-5.3-flash',
          'deepseek-v4.1-flash',
          'kimi-k2.7-code',
          'qwen3.8-flash',
        ];
        for (final id in preferred) {
          for (final item in pool) {
            if (item.id == id) {
              model = item;
              break;
            }
          }
          if (model != null) break;
        }
      }
      model ??= pool.first;
    }
    if (model == null) {
      // Selected provider has no model for this mode; fall back to demo for a
      // consistent, non-crashing UX.
      final demo = byId('demo');
      if (demo != null) {
        final demoPool = imageMode ? demo.imageModels : demo.chatModels;
        if (demoPool.isNotEmpty) {
          return ModelSelection(demo, demoPool.first);
        }
      }
      throw StateError('当前没有可用的模型，请先在设置中配置厂商。');
    }
    return ModelSelection(provider, model);
  }

  Future<String> apiKeyFor(String providerId) async {
    final provider = byId(providerId);
    if (provider?.demo == true) return 'demo';
    return await repo.apiKeyFor(providerId) ?? '';
  }

  Future<void> refreshModels(ProviderConfig provider, {bool silent = false}) async {
    if (provider.demo) return;
    if (syncing.contains(provider.id)) return;
    syncing.add(provider.id);
    notifyListeners();
    try {
      final key = await apiKeyFor(provider.id);
      if (key.isEmpty) {
        throw const HttpExceptionLike('请先填写 API Key。');
      }
      final models = await _sync.fetchModels(provider, key);
      final merged = mergeSyncedModels(synced: models, current: provider.models);
      _replace(
        provider.copyWith(
          models: merged,
          modelsSyncedAt: DateTime.now(),
          clearSyncError: true,
        ),
        save: true,
      );
    } catch (error) {
      _replace(
        provider.copyWith(
          syncError: friendlyNetworkError(error),
          modelsSyncedAt: provider.modelsSyncedAt,
        ),
        save: true,
      );
      if (!silent) rethrow;
    } finally {
      syncing.remove(provider.id);
      notifyListeners();
    }
  }

  Future<void> refreshAll() async {
    for (final provider in List<ProviderConfig>.from(providers)) {
      if (provider.demo || !provider.enabled || !provider.hasKey) continue;
      try {
        await refreshModels(provider, silent: true);
      } catch (_) {
        // Continue with the next provider.
      }
    }
  }

  Future<void> saveProvider(
    ProviderConfig provider, {
    String? apiKey,
    bool clearKey = false,
    bool syncAfterSave = true,
  }) async {
    await repo.saveProvider(provider, apiKey: apiKey, clearKey: clearKey);
    final refreshed = provider.copyWith(
      hasKey: clearKey
          ? false
          : (apiKey != null && apiKey.isNotEmpty ? true : provider.hasKey),
    );
    final index = providers.indexWhere((p) => p.id == refreshed.id);
    if (index >= 0) {
      providers[index] = refreshed;
    } else {
      providers.add(refreshed);
      providers.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    notifyListeners();
    if (syncAfterSave && refreshed.hasKey && !refreshed.demo) {
      unawaited(refreshModels(refreshed, silent: true));
    }
  }

  Future<void> updateModel(ProviderConfig provider, ModelInfo model) async {
    final models = <ModelInfo>[
      for (final existing in provider.models)
        if (existing.id == model.id) model else existing,
    ];
    if (!models.any((existing) => existing.id == model.id)) {
      models.add(model);
    }
    await saveProvider(
      provider.copyWith(models: models),
      syncAfterSave: false,
    );
  }

  Future<void> removeModel(ProviderConfig provider, String modelId) async {
    await saveProvider(
      provider.copyWith(
        models: provider.models.where((model) => model.id != modelId).toList(growable: false),
      ),
      syncAfterSave: false,
    );
  }

  Future<void> deleteProvider(ProviderConfig provider) async {
    if (provider.demo) return;
    await repo.deleteProvider(provider);
    providers.removeWhere((p) => p.id == provider.id);
    notifyListeners();
  }

  void _replace(ProviderConfig provider, {bool save = false}) {
    final index = providers.indexWhere((p) => p.id == provider.id);
    if (index >= 0) {
      providers[index] = provider;
    } else {
      providers.add(provider);
    }
    if (save) {
      unawaited(repo.db.saveProvider(provider));
    }
    notifyListeners();
  }
}

class ConversationsController extends ChangeNotifier {
  ConversationsController(this.repo);

  final AppRepository repo;
  List<Conversation> conversations = [];
  bool loading = true;

  Future<void> load() async {
    conversations = await repo.db.loadConversations();
    loading = false;
    _sort();
    notifyListeners();
  }

  void _sort() {
    conversations.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  Conversation? byId(String id) {
    for (final conversation in conversations) {
      if (conversation.id == id) return conversation;
    }
    return null;
  }

  Future<Conversation> create({
    required String providerId,
    required String modelId,
    ReasoningLevel reasoning = ReasoningLevel.auto,
  }) async {
    final conversation = Conversation(
      id: newId('conv'),
      title: '新对话',
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      providerId: providerId,
      modelId: modelId,
      reasoningLevel: reasoning,
    );
    await repo.db.saveConversation(conversation);
    conversations.add(conversation);
    _sort();
    notifyListeners();
    return conversation;
  }

  Future<void> save(Conversation conversation, {bool touch = true}) async {
    if (touch) conversation.updatedAt = DateTime.now().toUtc();
    final index = conversations.indexWhere((c) => c.id == conversation.id);
    if (index >= 0) {
      conversations[index] = conversation;
    } else {
      conversations.add(conversation);
    }
    _sort();
    notifyListeners();
    await repo.db.saveConversation(conversation);
  }

  Future<void> rename(Conversation conversation, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return;
    conversation.title = clean;
    await save(conversation);
  }

  Future<void> setPinned(Conversation conversation, bool pinned) async {
    conversation.pinned = pinned;
    await save(conversation);
  }

  Future<void> delete(Conversation conversation) async {
    await repo.db.deleteConversation(conversation.id);
    conversations.removeWhere((c) => c.id == conversation.id);
    notifyListeners();
  }

  Future<void> clearAll() async {
    await repo.db.clearConversations();
    conversations.clear();
    notifyListeners();
  }
}

class MemoriesController extends ChangeNotifier {
  MemoriesController(this.repo);

  final AppRepository repo;
  UserProfile profile = UserProfile();
  List<MemoryItem> memories = [];
  bool loading = true;
  bool busy = false;

  Future<void> load() async {
    profile = await repo.db.loadProfile();
    memories = await repo.db.loadMemories();
    loading = false;
    notifyListeners();
  }

  Future<void> saveProfile(UserProfile next) async {
    profile = next;
    notifyListeners();
    await repo.db.saveProfile(next);
  }

  Future<MemoryItem> addMemory(
    String content, {
    MemoryCategory category = MemoryCategory.other,
    int importance = 3,
    bool manual = true,
  }) async {
    final clean = content.trim();
    final item = MemoryItem(
      id: newId('mem'),
      content: clean,
      category: category,
      importance: importance.clamp(1, 5),
      confidence: 1,
      createdAt: DateTime.now().toUtc(),
      manual: manual,
      pinned: manual,
    );
    memories.insert(0, item);
    notifyListeners();
    await repo.db.saveMemory(item);
    return item;
  }

  Future<void> updateMemory(MemoryItem memory) async {
    final index = memories.indexWhere((m) => m.id == memory.id);
    if (index >= 0) memories[index] = memory;
    notifyListeners();
    await repo.db.saveMemory(memory);
  }

  Future<void> deleteMemory(MemoryItem memory) async {
    memories.removeWhere((m) => m.id == memory.id);
    notifyListeners();
    await repo.db.deleteMemory(memory.id);
  }

  Future<void> togglePinned(MemoryItem memory) async {
    memory.pinned = !memory.pinned;
    await updateMemory(memory);
  }

  Future<void> clearAll() async {
    memories.clear();
    profile = UserProfile();
    notifyListeners();
    await repo.db.clearMemories();
    await repo.db.saveProfile(profile);
  }

  Future<void> loadSample() async {
    await repo.db.clearMemories();
    profile = sampleProfile();
    memories = sampleMemories();
    notifyListeners();
    await repo.db.saveProfile(profile);
    for (final memory in memories) {
      await repo.db.saveMemory(memory);
    }
  }

  MemoryBundle exportBundle() => MemoryBundle(
        profile: profile,
        memories: List<MemoryItem>.from(memories),
        exportedAt: nowUtc(),
      );

  Future<MemoryImportResult> importBundle(
    MemoryBundle bundle, {
    required MemoryImportMode mode,
  }) async {
    if (mode == MemoryImportMode.replace) {
      final imported = [
        for (final memory in bundle.memories)
          MemoryItem(
            id: newId('mem'),
            content: memory.content.trim(),
            category: memory.category,
            importance: memory.importance.clamp(1, 5),
            confidence: memory.confidence.clamp(0, 1),
            createdAt: memory.createdAt,
            lastUsedAt: memory.lastUsedAt,
            pinned: memory.pinned,
            manual: memory.manual,
          ),
      ];
      final nextProfile = bundle.profile.copyWith(
        updatedAt: bundle.profile.updatedAt ?? nowUtc(),
      );
      await repo.db.replaceMemories(nextProfile, imported);
      profile = nextProfile;
      memories = imported;
      notifyListeners();
      return MemoryImportResult(
        added: imported.length,
        updated: 0,
        skipped: 0,
        replaced: true,
      );
    }

    var added = 0;
    var updated = 0;
    var skipped = 0;
    final nextProfile = profile.copyWith();
    var profileChanged = false;

    void fillScalar(String incoming, String current, void Function(String) setter) {
      if (incoming.trim().isNotEmpty && current.trim().isEmpty) {
        setter(incoming.trim());
        profileChanged = true;
      }
    }

    void mergeList(
      List<String> incoming,
      List<String> current,
      void Function(List<String>) setter,
    ) {
      if (incoming.isEmpty) return;
      final seen = current.map(_normalize).toSet();
      final merged = [...current];
      for (final value in incoming) {
        final key = _normalize(value);
        if (key.isEmpty || seen.contains(key)) continue;
        seen.add(key);
        merged.add(value);
        profileChanged = true;
      }
      if (merged.length != current.length) setter(merged.take(30).toList());
    }

    fillScalar(bundle.profile.name, nextProfile.name, (v) => nextProfile.name = v);
    fillScalar(bundle.profile.occupation, nextProfile.occupation, (v) => nextProfile.occupation = v);
    fillScalar(bundle.profile.location, nextProfile.location, (v) => nextProfile.location = v);
    fillScalar(bundle.profile.education, nextProfile.education, (v) => nextProfile.education = v);
    fillScalar(bundle.profile.thinkingStyle, nextProfile.thinkingStyle, (v) => nextProfile.thinkingStyle = v);
    fillScalar(bundle.profile.summary, nextProfile.summary, (v) => nextProfile.summary = v);
    mergeList(bundle.profile.personality, nextProfile.personality, (v) => nextProfile.personality = v);
    mergeList(bundle.profile.expertise, nextProfile.expertise, (v) => nextProfile.expertise = v);
    mergeList(bundle.profile.interests, nextProfile.interests, (v) => nextProfile.interests = v);
    mergeList(bundle.profile.values, nextProfile.values, (v) => nextProfile.values = v);
    mergeList(bundle.profile.goals, nextProfile.goals, (v) => nextProfile.goals = v);
    mergeList(
      bundle.profile.communicationStyle,
      nextProfile.communicationStyle,
      (v) => nextProfile.communicationStyle = v,
    );
    if (profileChanged) {
      nextProfile.version = profile.version + 1;
      nextProfile.updatedAt = nowUtc();
      profile = nextProfile;
      await repo.db.saveProfile(profile);
    }

    for (final incoming in bundle.memories) {
      final content = incoming.content.trim();
      if (content.isEmpty) {
        skipped++;
        continue;
      }
      MemoryItem? duplicate;
      for (final existing in memories) {
        if (_similar(existing.content, content)) {
          duplicate = existing;
          break;
        }
      }
      if (duplicate != null) {
        var changed = false;
        if (incoming.importance > duplicate.importance) {
          duplicate.importance = incoming.importance.clamp(1, 5);
          changed = true;
        }
        if (incoming.confidence > duplicate.confidence) {
          duplicate.confidence = incoming.confidence.clamp(0, 1);
          changed = true;
        }
        if (incoming.pinned && !duplicate.pinned) {
          duplicate.pinned = true;
          changed = true;
        }
        if (changed) {
          updated++;
          await repo.db.saveMemory(duplicate);
        } else {
          skipped++;
        }
        continue;
      }
      final item = MemoryItem(
        id: newId('mem'),
        content: content,
        category: incoming.category,
        importance: incoming.importance.clamp(1, 5),
        confidence: incoming.confidence.clamp(0, 1),
        createdAt: incoming.createdAt,
        lastUsedAt: incoming.lastUsedAt,
        pinned: incoming.pinned,
        manual: incoming.manual,
      );
      memories.insert(0, item);
      added++;
      await repo.db.saveMemory(item);
    }
    if (added > 0 || updated > 0 || profileChanged) notifyListeners();
    return MemoryImportResult(
      added: added,
      updated: updated,
      skipped: skipped,
      replaced: false,
    );
  }

  Future<String> saveMemoryTool(
    String content,
    MemoryCategory category,
    int importance,
  ) async {
    final clean = content.trim();
    if (clean.isEmpty) return '记忆内容为空，未保存。';
    for (final existing in memories) {
      if (_normalize(existing.content) == _normalize(clean)) {
        existing.importance = existing.importance > importance ? existing.importance : importance;
        existing.lastUsedAt = DateTime.now().toUtc();
        await updateMemory(existing);
        return '这条信息已经在长期记忆里了，已提高其重要性。';
      }
    }
    await addMemory(clean, category: category, importance: importance, manual: false);
    return '已写入长期记忆：$clean';
  }

  Future<String> searchMemoryTool(String query) async {
    final selected = retrieve(query, limit: 6);
    if (selected.isEmpty) return '没有找到相关的长期记忆。';
    final buffer = StringBuffer('相关长期记忆：\n');
    for (final memory in selected) {
      buffer.writeln('- [${memory.category.label}] ${memory.content}');
    }
    return buffer.toString().trim();
  }

  List<MemoryItem> retrieve(String query, {int limit = 8}) {
    if (memories.isEmpty) return const [];
    final queryTokens = _tokens(query);
    final scored = <(MemoryItem, double)>[];
    for (final memory in memories) {
      final tokens = _tokens(memory.content);
      var overlap = 0.0;
      for (final token in queryTokens) {
        if (tokens.contains(token)) overlap += 1;
      }
      final relevance = queryTokens.isEmpty ? 0.0 : overlap / (queryTokens.length * 0.75 + 1);
      final ageDays = DateTime.now().difference(memory.createdAt.toLocal()).inDays.clamp(0, 3650);
      final recency = 1 / (1 + ageDays / 45);
      final score = relevance * 2.4 +
          memory.importance * 0.12 +
          memory.confidence * 0.15 +
          (memory.pinned ? 0.8 : 0) +
          recency * 0.2 +
          (memory.lastUsedAt == null
              ? 0
              : 1 / (1 + DateTime.now().difference(memory.lastUsedAt!.toLocal()).inDays / 30) * 0.1);
      if (relevance > 0 || memory.pinned || queryTokens.isEmpty) {
        scored.add((memory, score));
      }
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final selected = scored.take(limit).map((e) => e.$1).toList();
    for (final memory in selected) {
      memory.lastUsedAt = DateTime.now().toUtc();
    }
    return selected;
  }

  String buildMemoryPrompt(String query) {
    if (profile.isEmpty && memories.isEmpty) return '';
    final buffer = StringBuffer('## 你了解的用户\n');
    buffer.writeln('以下是保存在本机的长期记忆，可能不完整或过时。相关时自然使用，不要逐条复述，也不要声称“根据我的记忆”。\n');
    final profileText = profile.toPrompt();
    if (profileText.isNotEmpty) buffer.writeln(profileText);
    final selected = retrieve(query, limit: 8);
    if (selected.isNotEmpty) {
      buffer.writeln('\n### 相关记忆');
      for (final memory in selected) {
        buffer.writeln('- [${memory.category.label}] ${memory.content}');
      }
    }
    return buffer.toString().trim();
  }

  Future<int> mergeExtraction(Map<String, dynamic> json, String conversationId) async {
    final oldProfile = profile.copyWith();
    final updates = json['profile_updates'];
    var changed = 0;
    var touched = false;
    if (updates is Map) {
      final map = updates.map((k, v) => MapEntry('$k', v));
      String read(String key) => '${map[key] ?? ''}'.trim();
      List<String> readList(String key) {
        final value = map[key];
        if (value is List) {
          return value.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
        }
        return const [];
      }

      final next = profile.copyWith();
      var touched = false;
      void setScalar(String value, String Function() getter, void Function(String) setter) {
        if (value.isNotEmpty && value != getter()) {
          setter(value);
          touched = true;
        }
      }

      setScalar(read('name'), () => next.name, (v) => next.name = v);
      setScalar(read('occupation'), () => next.occupation, (v) => next.occupation = v);
      setScalar(read('location'), () => next.location, (v) => next.location = v);
      setScalar(read('education'), () => next.education, (v) => next.education = v);
      setScalar(read('thinkingStyle'), () => next.thinkingStyle, (v) => next.thinkingStyle = v);
      if (read('summary').isNotEmpty && read('summary') != next.summary) {
        next.summary = read('summary');
        touched = true;
      }
      void mergeList(List<String> incoming, List<String> current, void Function(List<String>) setter) {
        if (incoming.isEmpty) return;
        final existing = current.map(_normalize).toSet();
        final merged = [...current];
        for (final value in incoming) {
          final key = _normalize(value);
          if (key.isEmpty || existing.contains(key)) continue;
          existing.add(key);
          merged.add(value);
        }
        if (merged.length != current.length) {
          setter(merged.take(20).toList());
          touched = true;
        }
      }

      mergeList(readList('personality'), next.personality, (v) => next.personality = v);
      mergeList(readList('expertise'), next.expertise, (v) => next.expertise = v);
      mergeList(readList('interests'), next.interests, (v) => next.interests = v);
      mergeList(readList('values'), next.values, (v) => next.values = v);
      mergeList(readList('goals'), next.goals, (v) => next.goals = v);
      mergeList(readList('communicationStyle'), next.communicationStyle, (v) => next.communicationStyle = v);
      if (touched) {
        next.version = profile.version + 1;
        next.updatedAt = DateTime.now().toUtc();
        profile = next;
        await repo.db.saveProfile(profile);
        changed++;
      }
    }

    final rawMemories = json['memories'];
    if (rawMemories is List) {
      for (final raw in rawMemories) {
        if (raw is! Map) continue;
        final map = raw.map((k, v) => MapEntry('$k', v));
        final content = '${map['content'] ?? ''}'.trim();
        if (content.length < 4) continue;
        final category = MemoryCategory.values.firstWhere(
          (c) => c.name == '${map['category']}',
          orElse: () => MemoryCategory.other,
        );
        final importance = ((map['importance'] as num?)?.toInt() ?? 3).clamp(1, 5);
        final confidence = ((map['confidence'] as num?)?.toDouble() ?? 0.75).clamp(0.0, 1.0);
        MemoryItem? duplicate;
        for (final existing in memories) {
          if (_similar(existing.content, content) ||
              _profileValueChanged(
                existing.content,
                content,
                oldProfile,
                profile,
              )) {
            duplicate = existing;
            break;
          }
        }
        if (duplicate != null) {
          var duplicateChanged = false;
          if (_looksLikeFactUpdate(
            duplicate.content,
            content,
            oldProfile,
            profile,
          )) {
            duplicate.content = content;
            duplicate.category = category;
            duplicate.sourceConversationId = conversationId;
            changed++;
            duplicateChanged = true;
          }
          if (importance > duplicate.importance) {
            duplicate.importance = importance;
            duplicateChanged = true;
          }
          if (confidence > duplicate.confidence) {
            duplicate.confidence = confidence;
            duplicateChanged = true;
          }
          duplicate.lastUsedAt = DateTime.now().toUtc();
          if (duplicateChanged) touched = true;
          await repo.db.saveMemory(duplicate);
        } else {
          final item = MemoryItem(
            id: newId('mem'),
            content: content,
            category: category,
            importance: importance,
            confidence: confidence,
            sourceConversationId: conversationId,
            createdAt: DateTime.now().toUtc(),
          );
          memories.insert(0, item);
          await repo.db.saveMemory(item);
          changed++;
        }
      }
    }
    if (changed > 0 || touched) notifyListeners();
    return changed;
  }
}

class McpController extends ChangeNotifier {
  McpController(this.repo) : service = McpService();

  final AppRepository repo;
  final McpService service;
  List<McpServerConfig> servers = [];
  bool loading = true;
  final Set<String> syncing = {};

  Future<void> load() async {
    servers = await repo.db.loadMcpServers();
    loading = false;
    notifyListeners();
  }

  Map<String, List<McpToolInfo>> get toolsByServer => {
        for (final server in servers)
          if (server.enabled) server.id: server.tools,
      };

  bool get supportsStdio => service.supportsLocalStdio;

  Future<void> save(McpServerConfig server) async {
    final index = servers.indexWhere((s) => s.id == server.id);
    if (index >= 0) {
      servers[index] = server;
    } else {
      servers.add(server);
    }
    notifyListeners();
    await repo.db.saveMcpServer(server);
  }

  Future<void> delete(McpServerConfig server) async {
    servers.removeWhere((s) => s.id == server.id);
    notifyListeners();
    await repo.db.deleteMcpServer(server.id);
  }

  Future<McpServerConfig> refreshTools(McpServerConfig server) async {
    if (syncing.contains(server.id)) return server;
    syncing.add(server.id);
    notifyListeners();
    McpServerConfig updated;
    try {
      final tools = await service.listTools(server);
      updated = server.copyWith(
        tools: tools,
        lastSyncedAt: DateTime.now(),
        clearError: true,
      );
    } catch (error) {
      updated = server.copyWith(error: '$error');
    } finally {
      syncing.remove(server.id);
    }
    final index = servers.indexWhere((s) => s.id == updated.id);
    if (index >= 0) servers[index] = updated;
    notifyListeners();
    await repo.db.saveMcpServer(updated);
    return updated;
  }

  Future<void> refreshAll() async {
    for (final server in List<McpServerConfig>.from(servers)) {
      if (!server.enabled) continue;
      await refreshTools(server);
    }
  }
}

class HttpExceptionLike implements Exception {
  const HttpExceptionLike(this.message);
  final String message;

  @override
  String toString() => message;
}

Set<String> _tokens(String text) {
  final tokens = <String>{};
  final lower = text.toLowerCase();
  for (final match in RegExp(r'[a-z0-9]+').allMatches(lower)) {
    if (match.group(0)!.length >= 2) tokens.add(match.group(0)!);
  }
  final chinese = RegExp(r'[\u4e00-\u9fff]+').allMatches(lower);
  for (final match in chinese) {
    final value = match.group(0)!;
    for (var i = 0; i < value.length - 1; i++) {
      tokens.add(value.substring(i, i + 2));
    }
    if (value.length == 1) tokens.add(value);
  }
  return tokens;
}

String _normalize(String value) => value.toLowerCase().replaceAll(
      RegExp(r'''[\s，。！？,.!?、；;：:“”"'（）()\[\]【】]'''),
      '',
    );

bool _profileValueChanged(
  String oldText,
  String newText,
  UserProfile oldProfile,
  UserProfile newProfile,
) {
  final oldNorm = _normalize(oldText);
  final newNorm = _normalize(newText);
  final profilePairs = <(String, String)>[
    (oldProfile.name, newProfile.name),
    (oldProfile.occupation, newProfile.occupation),
    (oldProfile.location, newProfile.location),
    (oldProfile.education, newProfile.education),
    (oldProfile.thinkingStyle, newProfile.thinkingStyle),
  ];
  for (final pair in profilePairs) {
    final oldValue = _normalize(pair.$1);
    final newValue = _normalize(pair.$2);
    if (oldValue.isEmpty || newValue.isEmpty || oldValue == newValue) continue;
    if (oldNorm.contains(oldValue) && newNorm.contains(newValue)) {
      return true;
    }
  }
  return false;
}

/// Similar text can still describe a changed fact. Only explicit update
/// signals are allowed to replace the stored content; otherwise a high
/// similarity score is treated as paraphrase and the entry is deduplicated.
bool _looksLikeFactUpdate(
  String oldText,
  String newText,
  UserProfile oldProfile,
  UserProfile newProfile,
) {
  final oldNorm = _normalize(oldText);
  final newNorm = _normalize(newText);
  if (oldNorm == newNorm) return false;

  if (_profileValueChanged(oldText, newText, oldProfile, newProfile)) {
    return true;
  }

  if (_hasNegation(oldNorm) != _hasNegation(newNorm)) return true;

  final oldNumbers = _numbersIn(oldNorm);
  final newNumbers = _numbersIn(newNorm);
  if (oldNumbers.isNotEmpty &&
      newNumbers.isNotEmpty &&
      (oldNumbers.length != newNumbers.length ||
          !oldNumbers.every(newNumbers.contains))) {
    return true;
  }

  const changeCues = [
    '现在',
    '目前',
    '已经',
    '搬到',
    '改为',
    '换成',
    '更新为',
    '不再',
    '转而',
    '现居',
    '现任',
    '新地址',
  ];
  final hasNewCue = changeCues.any(newNorm.contains);
  final hasOldCue = changeCues.any(oldNorm.contains);
  return hasNewCue && !hasOldCue;
}

bool _hasNegation(String value) => RegExp(
      r'(不喜欢|不想|不爱|不再|没有|不是|不会|不能|从未|从不|并不|不常|不喝|不吃|不去|不玩|不读|不看|不用|无须|无需)',
    ).hasMatch(value);

List<String> _numbersIn(String value) =>
    RegExp(r'\d+(?:\.\d+)?').allMatches(value).map((match) => match.group(0)!).toList();

bool _similar(String a, String b) {
  final na = _normalize(a);
  final nb = _normalize(b);
  if (na == nb) return true;
  if (na.length < 6 || nb.length < 6) return false;
  final ta = _bigrams(na);
  final tb = _bigrams(nb);
  if (ta.isEmpty || tb.isEmpty) return false;
  final intersection = ta.intersection(tb).length;
  final union = ta.union(tb).length;
  return intersection / union >= 0.8;
}

Set<String> _bigrams(String value) {
  final set = <String>{};
  for (var i = 0; i < value.length - 1; i++) {
    set.add(value.substring(i, i + 2));
  }
  return set;
}
