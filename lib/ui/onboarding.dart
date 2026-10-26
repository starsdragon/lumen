import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../services/controllers.dart';
import 'common/widgets.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _key = TextEditingController();
  final TextEditingController _baseUrl = TextEditingController();
  String _selectedId = 'deepseek';
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final providers = context.read<ProvidersController>();
      final preferred = providers.byId(_selectedId);
      if (preferred != null) _baseUrl.text = preferred.baseUrl;
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  void _select(ProviderConfig provider) {
    setState(() {
      _selectedId = provider.id;
      _baseUrl.text = provider.baseUrl;
      _error = null;
    });
  }

  Future<void> _startDemo() async {
    final settings = context.read<SettingsController>();
    final providers = context.read<ProvidersController>();
    final demo = providers.byId('demo');
    await settings.update(
      settings.settings.copyWith(
        onboardingDone: true,
        defaultProviderId: 'demo',
        defaultModelId: 'lumen-demo',
        lastUsedProviderId: demo?.id ?? 'demo',
        lastUsedModelId: 'lumen-demo',
      ),
    );
  }

  Future<void> _saveAndStart() async {
    final key = _key.text.trim();
    final providers = context.read<ProvidersController>();
    final settings = context.read<SettingsController>();
    final provider = providers.byId(_selectedId);
    if (provider == null) return;
    if (key.isEmpty) {
      setState(() => _error = '请填写 API Key，或选择“先体验演示”。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final base = normalizeBaseUrl(_baseUrl.text.trim().isEmpty ? provider.baseUrl : _baseUrl.text);
      final updated = provider.copyWith(baseUrl: base, enabled: true);
      await providers.saveProvider(updated, apiKey: key);
      final refreshed = providers.byId(provider.id) ?? updated;
      final model = refreshed.chatModels.isNotEmpty ? refreshed.chatModels.first : null;
      await settings.update(
        settings.settings.copyWith(
          onboardingDone: true,
          defaultProviderId: refreshed.id,
          defaultModelId: model?.id ?? refreshed.models.firstOrNull?.id ?? '',
          lastUsedProviderId: refreshed.id,
          lastUsedModelId: model?.id ?? refreshed.models.firstOrNull?.id ?? '',
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = friendlyNetworkError(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final providers = context.watch<ProvidersController>();
    final builtins = providers.providers
        .where((p) => p.builtin && !p.demo && p.id != 'custom')
        .toList(growable: false);
    final selected = providers.byId(_selectedId) ?? builtins.firstOrNull;

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -180,
            left: -140,
            child: _Glow(color: c.primary.withValues(alpha: 0.14), size: 520),
          ),
          Positioned(
            bottom: -220,
            right: -120,
            child: _Glow(color: const Color(0xFF7A5CFF).withValues(alpha: 0.10), size: 560),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > 940;
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 60 : 24,
                    vertical: wide ? 40 : 26,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 1120,
                        minHeight: wide ? constraints.maxHeight - 80 : 0,
                      ),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(child: _Hero(c: c)),
                                const SizedBox(width: 56),
                                SizedBox(width: 430, child: _connectCard(context, selected, builtins)),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Hero(c: c, compact: true),
                                const SizedBox(height: 26),
                                _connectCard(context, selected, builtins),
                              ],
                            ),
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

  Widget _connectCard(
    BuildContext context,
    ProviderConfig? selected,
    List<ProviderConfig> builtins,
  ) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(color: c.shadow, blurRadius: 40, offset: const Offset(0, 16)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('连接一个模型', style: context.text.titleLarge),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: c.border),
                ),
                child: Text(
                  '可选',
                  style: context.text.labelSmall?.copyWith(color: c.textTertiary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '填一个你已有的 API Key，或先用演示模式体验完整界面。',
            style: context.text.bodySmall?.copyWith(color: c.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final provider in builtins)
                _ProviderChoice(
                  provider: provider,
                  selected: provider.id == _selectedId,
                  onTap: () => _select(provider),
                ),
            ],
          ),
          if (selected != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  Icon(
                    selected.protocol == LlmProtocol.openai
                        ? Icons.swap_horiz_rounded
                        : selected.protocol == LlmProtocol.anthropic
                            ? Icons.terminal_rounded
                            : Icons.cloud_outlined,
                    size: 16,
                    color: c.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${selected.protocol.label} · ${selected.description}',
                      style: context.text.labelSmall?.copyWith(color: c.textSecondary, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: '粘贴平台控制台里的 Key',
                prefixIcon: const Icon(Icons.key_rounded, size: 18),
                suffixIcon: IconButton(
                  tooltip: _obscure ? '显示' : '隐藏',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 9),
            TextField(
              controller: _baseUrl,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontSize: 12.5),
              decoration: const InputDecoration(
                labelText: 'Base URL（中转站可改）',
                prefixIcon: Icon(Icons.link_rounded, size: 18),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: context.text.bodySmall?.copyWith(color: c.danger, height: 1.45),
              ),
            ],
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 47,
              child: FilledButton(
                onPressed: _saving ? null : _saveAndStart,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('保存并开始'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 43,
              child: OutlinedButton(
                onPressed: _saving ? null : _startDemo,
                child: const Text('先体验演示模式'),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 13, color: c.textTertiary),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'API Key 只保存在本机系统安全存储中；对话会直接发送给你选择的模型厂商。',
                    style: context.text.labelSmall?.copyWith(color: c.textTertiary, height: 1.45),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.c, this.compact = false});

  final LumenColors c;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const LumenMark(size: 42),
            const SizedBox(width: 11),
            Text(
              'Lumen',
              style: context.text.titleLarge?.copyWith(
                fontSize: 21,
                letterSpacing: -0.3,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: c.primarySoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'AGENT',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: c.primary,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 26 : 42),
        Text(
          '一个会记住你的\nAI 伙伴',
          style: context.text.displaySmall?.copyWith(
            fontSize: compact ? 32 : 46,
            height: 1.2,
            letterSpacing: compact ? -0.8 : -1.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 13),
        Text(
          '把长期记忆、多厂商模型、联网搜索、MCP 工具与生图放进一个安静、可靠的对话界面。',
          style: context.text.bodyLarge?.copyWith(
            color: c.textSecondary,
            fontSize: compact ? 14 : 16,
            height: 1.65,
          ),
        ),
        SizedBox(height: compact ? 22 : 30),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: const [
            _Feature(icon: Icons.auto_awesome_outlined, title: '越聊越懂你', text: '画像 + 长期记忆'),
            _Feature(icon: Icons.hub_outlined, title: '一个入口', text: 'DeepSeek / GLM / Kimi…'),
            _Feature(icon: Icons.travel_explore_rounded, title: '联网有据', text: '来源可核查'),
            _Feature(icon: Icons.extension_outlined, title: '可扩展', text: 'MCP 工具生态'),
            _Feature(icon: Icons.image_outlined, title: '能看能画', text: '图片输入与生成'),
            _Feature(icon: Icons.shield_outlined, title: '本地优先', text: '数据留在设备上'),
          ],
        ),
        SizedBox(height: compact ? 20 : 32),
        Row(
          children: [
            Icon(Icons.devices_rounded, size: 14, color: c.textTertiary),
            const SizedBox(width: 6),
            Text(
              '支持 OpenAI / Anthropic / Gemini 原生接口，以及任意 OpenAI 兼容中转站',
              style: context.text.labelSmall?.copyWith(color: c.textTertiary),
            ),
          ],
        ),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 158,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.text.labelSmall?.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(
                    color: c.textTertiary,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderChoice extends StatelessWidget {
  const _ProviderChoice({
    required this.provider,
    required this.selected,
    required this.onTap,
  });

  final ProviderConfig provider;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? c.primarySoft : c.surfaceAlt,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(7, 6, 9, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? c.primary.withValues(alpha: 0.45) : c.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProviderLogo(provider: provider, size: 20),
              const SizedBox(width: 6),
              Text(
                provider.name,
                style: context.text.labelSmall?.copyWith(
                  color: selected ? c.primary : c.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
