import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/controllers.dart';
import '../../services/search_service.dart';
import '../common/widgets.dart';

class SearchSettingsScreen extends StatefulWidget {
  const SearchSettingsScreen({super.key});

  @override
  State<SearchSettingsScreen> createState() => _SearchSettingsScreenState();
}

class _SearchSettingsScreenState extends State<SearchSettingsScreen> {
  late SearchProvider _provider;
  late int _maxResults;
  late bool _fetchContent;
  late final TextEditingController _tavily;
  late final TextEditingController _google;
  late final TextEditingController _googleCx;
  late final TextEditingController _bing;
  late final TextEditingController _searx;
  late final TextEditingController _domains;
  final TextEditingController _testQuery = TextEditingController(text: 'OpenAI 最新动态');
  final SearchService _search = SearchService();
  bool _obscure = true;
  bool _testing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsController>();
    final config = settings.settings.search;
    _provider = config.provider;
    _maxResults = config.maxResults;
    _fetchContent = config.fetchPageContent;
    _tavily = TextEditingController(text: settings.credentials.tavily);
    _google = TextEditingController(text: settings.credentials.google);
    _googleCx = TextEditingController(text: config.googleCx);
    _bing = TextEditingController(text: settings.credentials.bing);
    _searx = TextEditingController(text: config.searxBaseUrl);
    _domains = TextEditingController(text: config.includeDomains.join(', '));
  }

  @override
  void dispose() {
    _tavily.dispose();
    _google.dispose();
    _googleCx.dispose();
    _bing.dispose();
    _searx.dispose();
    _domains.dispose();
    _testQuery.dispose();
    super.dispose();
  }

  SearchConfig _buildConfig() => SearchConfig(
        provider: _provider,
        googleCx: _googleCx.text.trim(),
        searxBaseUrl: _searx.text.trim(),
        maxResults: _maxResults,
        fetchPageContent: _fetchContent,
        includeDomains: _domains.text
            .split(RegExp(r'[，,\n]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      );

  Future<void> _save({bool quiet = false}) async {
    final settings = context.read<SettingsController>();
    setState(() => _saving = true);
    try {
      await settings.setSearch(_buildConfig());
      await settings.setSearchKey(SearchProvider.tavily, _tavily.text);
      await settings.setSearchKey(SearchProvider.google, _google.text);
      await settings.setSearchKey(SearchProvider.bing, _bing.text);
      if (mounted && !quiet) showToast(context, '联网搜索设置已保存');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    if (_provider == SearchProvider.none) {
      showToast(context, '请先选择一个搜索服务。');
      return;
    }
    if (_testQuery.text.trim().isEmpty) {
      showToast(context, '请输入测试关键词。');
      return;
    }
    setState(() => _testing = true);
    try {
      await _save(quiet: true);
      if (!mounted) return;
      final settings = context.read<SettingsController>();
      final hits = await _search.search(
        _testQuery.text.trim(),
        config: _buildConfig(),
        credentials: settings.credentials,
      );
      if (!mounted) return;
      if (hits.isEmpty) {
        showToast(context, '搜索成功，但没有返回结果。');
        return;
      }
      await showLumenSheet<void>(
        context: context,
        builder: (context) => _TestResults(hits: hits),
      );
    } on SearchException catch (error) {
      if (mounted) {
        showToast(
          context,
          error.message,
          action: error.details == null
              ? null
              : SnackBarAction(
                  label: '详情',
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('搜索错误详情'),
                        content: SingleChildScrollView(child: SelectableText(error.details!)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      }
    } catch (error) {
      if (mounted) showToast(context, '搜索失败：$error');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('联网搜索'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(),
            child: const Text('保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择一个搜索服务。Tavily 与 Google/Bing API 需要 Key；也可以使用自建 SearXNG，或直接使用免费的 Bing 网页 / DuckDuckGo。',
                  style: context.text.bodySmall?.copyWith(color: c.textSecondary, height: 1.55),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth > 620 ? 2 : 1;
                    final width = columns == 2
                        ? (constraints.maxWidth - 8) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final provider in SearchProvider.values)
                          SizedBox(
                            width: width,
                            child: _ProviderTile(
                              provider: provider,
                              selected: _provider == provider,
                              onTap: () => setState(() => _provider = provider),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_iconFor(_provider), size: 18, color: c.primary),
                          const SizedBox(width: 8),
                          Text(_provider.label, style: context.text.titleMedium),
                          const Spacer(),
                          if (_provider.needsTavily || _provider.needsGoogle || _provider.needsBing)
                            IconButton(
                              tooltip: _obscure ? '显示 Key' : '隐藏 Key',
                              icon: Icon(
                                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                size: 18,
                              ),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _provider.hint,
                        style: context.text.labelSmall?.copyWith(color: c.textTertiary, height: 1.5),
                      ),
                      const SizedBox(height: 12),
                      if (_provider.needsTavily)
                        TextField(
                          controller: _tavily,
                          obscureText: _obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Tavily API Key',
                            hintText: 'tvly-...',
                            prefixIcon: Icon(Icons.key_rounded, size: 18),
                          ),
                        ),
                      if (_provider.needsGoogle) ...[
                        TextField(
                          controller: _google,
                          obscureText: _obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Google API Key',
                            prefixIcon: Icon(Icons.key_rounded, size: 18),
                          ),
                        ),
                        const SizedBox(height: 9),
                        TextField(
                          controller: _googleCx,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: '搜索引擎 ID (cx)',
                            helperText: '在 Programmable Search Engine 控制台创建',
                            prefixIcon: Icon(Icons.tag_rounded, size: 18),
                          ),
                        ),
                      ],
                      if (_provider.needsBing)
                        TextField(
                          controller: _bing,
                          obscureText: _obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Bing / Azure 订阅 Key',
                            helperText: 'Bing Search API 已停止新开通，老 Key 仍可使用',
                            prefixIcon: Icon(Icons.key_rounded, size: 18),
                          ),
                        ),
                      if (_provider.needsSearx)
                        TextField(
                          controller: _searx,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'SearXNG 实例地址',
                            hintText: 'https://searx.example.com',
                            helperText: '实例需在 settings.yml 中开启 JSON 输出',
                            prefixIcon: Icon(Icons.dns_outlined, size: 18),
                          ),
                        ),
                      if (_provider == SearchProvider.duckduckgo)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: c.surfaceAlt,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '无需 Key。应用会读取 DuckDuckGo 的公开结果页；部分网络环境可能被验证码或代理拦截，此时建议改用 Tavily 或自建 SearXNG。',
                            style: context.text.labelSmall?.copyWith(
                              color: c.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ),
                      if (_provider == SearchProvider.none)
                        Text(
                          '已关闭。模型不会获得联网工具。',
                          style: context.text.bodySmall?.copyWith(color: c.textSecondary),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text('返回结果数', style: context.text.bodyMedium),
                          const Spacer(),
                          Text(
                            '$_maxResults',
                            style: context.text.labelLarge?.copyWith(color: c.primary),
                          ),
                        ],
                      ),
                      Slider(
                        value: _maxResults.toDouble(),
                        min: 3,
                        max: 10,
                        divisions: 7,
                        onChanged: (value) => setState(() => _maxResults = value.round()),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('抓取网页正文'),
                        subtitle: const Text('更完整，但会增加搜索耗时；默认只读摘要'),
                        value: _fetchContent,
                        onChanged: (value) => setState(() => _fetchContent = value),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _domains,
                        style: context.text.bodySmall,
                        decoration: const InputDecoration(
                          labelText: '限定域名（可选，逗号分隔）',
                          hintText: 'example.com, docs.example.com',
                          prefixIcon: Icon(Icons.filter_alt_outlined, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _testQuery,
                        decoration: const InputDecoration(
                          labelText: '测试关键词',
                          prefixIcon: Icon(Icons.search_rounded, size: 18),
                        ),
                        onSubmitted: (_) => _test(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: _testing ? null : _test,
                        icon: _testing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 1.8),
                              )
                            : const Icon(Icons.play_arrow_rounded, size: 17),
                        label: const Text('测试'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 47,
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(),
                    child: _saving
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('保存设置'),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '搜索结果会交给模型综合。回答正文不插入来源编号，本次使用的网页统一收在回答下方的来源卡片里；网页内容只作为证据，不会被当作指令执行。',
                  style: context.text.labelSmall?.copyWith(color: c.textTertiary, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(SearchProvider provider) => switch (provider) {
        SearchProvider.tavily => Icons.hub_outlined,
        SearchProvider.google => Icons.search_rounded,
        SearchProvider.bing => Icons.window_rounded,
        SearchProvider.bingFree => Icons.travel_explore_rounded,
        SearchProvider.searxng => Icons.dns_outlined,
        SearchProvider.duckduckgo => Icons.public_rounded,
        SearchProvider.none => Icons.block_rounded,
      };
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({required this.provider, required this.selected, required this.onTap});

  final SearchProvider provider;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? c.primarySoft : c.surface,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? c.primary.withValues(alpha: 0.4) : c.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? c.surface : c.surfaceAlt,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  switch (provider) {
                    SearchProvider.tavily => Icons.hub_outlined,
                    SearchProvider.google => Icons.search_rounded,
                    SearchProvider.bing => Icons.window_rounded,
                    SearchProvider.bingFree => Icons.travel_explore_rounded,
                    SearchProvider.searxng => Icons.dns_outlined,
                    SearchProvider.duckduckgo => Icons.public_rounded,
                    SearchProvider.none => Icons.block_rounded,
                  },
                  size: 16,
                  color: selected ? c.primary : c.textSecondary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelMedium?.copyWith(
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? c.primary : c.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      provider == SearchProvider.none
                          ? '关闭联网'
                          : (provider == SearchProvider.duckduckgo || provider == SearchProvider.bingFree
                              ? '无需 Key'
                              : '需要配置'),
                      style: context.text.labelSmall?.copyWith(
                        color: c.textTertiary,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle_rounded, size: 17, color: c.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _TestResults extends StatelessWidget {
  const _TestResults({required this.hits});

  final List<SearchHit> hits;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.65,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 10, 8),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 18, color: c.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('搜索成功 · ${hits.length} 条结果', style: context.text.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              itemCount: hits.length,
              separatorBuilder: (_, _) => Divider(height: 12, color: c.border),
              itemBuilder: (context, index) {
                final hit = hits[index];
                return InkWell(
                  onTap: hit.url.isEmpty
                      ? null
                      : () async {
                          try {
                            await launchUrl(Uri.parse(hit.url), mode: LaunchMode.externalApplication);
                          } catch (_) {
                            // Ignore.
                          }
                        },
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${index + 1}. ${hit.title}',
                          style: context.text.labelMedium?.copyWith(
                            color: c.primary,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hit.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                        ),
                        if (hit.snippet.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            hit.snippet,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall?.copyWith(
                              color: c.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
