# DeepSeek App 分析与 Lumen 的设计取舍

> 分析对象：用户提供的 `base(1).apk`，包名 `com.deepseek.chat`，版本 2.7.0（versionCode 285），minSdk 24 / targetSdk 36，编译 SDK 36。
> 方法：`aapt2 dump badging`、apktool 资源解码、AndroidManifest / strings / colors / drawable / assets / native 库清单检查。未反编译业务代码，也未复制其代码、图像或文案。
> 参考对象（思考参数）：开源项目 [RikkaHub](https://github.com/rikkahub/rikkahub) 的 provider 实现与官方 API 文档。

## 1. 可确认的工程事实

| 维度 | 观察 |
|---|---|
| UI 框架 | Compose（资源中出现 `androidx_compose_foundation_autofill` 等） |
| 品牌色 | `primary = #FF426EFE`（接近 `#426EFE` 的蓝） |
| 启动背景 | `splashscreenBackground = #FFFFFFFF`，DayNight 主题 |
| 包体 | 约 22 MB；`classes.dex`、`classes2.dex`、`classes3.dex` 三个 dex |
| 原生库 | 仅 `arm64-v8a`：`libWCDB.so`、`libmmkv.so`、`libliteavsdk.so`、`libtxffmpeg.so`、`libtxsoundtouch.so`、`libEncryptorP.so`、`librscrypto.so`、`libapminsighta/b.so` 等 |
| 启动优化 | `assets/dexopt/baseline.prof` + `baseline.profm` |
| 公式渲染 | `assets/org/scilab/forge/jlatexmath/...`（LaTeX 字体与配置） |
| 动效资源 | `assets/shaders/fluid_blob*.frag/vert/agsl`（语音通话的流体光斑效果） |
| 语音能力 | LiteAV SDK、WebRTC 相关资源、通话/字幕/打断/评分等大量字符串 |
| 文件能力 | 支持图片、PDF、Office、文本、代码等 MIME 的分享入口；上传面板有 OCR / 文本提取提示 |
| 本地存储 | WCDB（SQLite 封装，常见于腾讯系）、MMKV（键值存储） |
| 监控 | 腾讯 APMPlus（`apmplus_hybrid`、`mobile_report_inject.js`） |
| 其他 | 微信登录/绑定、分享代理 Activity、通知、相机/录音权限、WebView 监控脚本 |

> 上述库的用途是行业常见组合，具体到 DeepSeek 的内部调用关系只能从资源与库存在性推断；本文不把推断写成结论。

## 2. UI / 交互设计要点

从资源字符串和品牌资源可还原出的主要界面：

- **欢迎页**：蓝色鲸鱼 Logo、`Welcome to DeepSeek`、两句产品说明（跨设备历史、AI 可能出错）。
- **双模型模式**：`Instant`（日常快速）与 `Expert`（复杂问题、高峰期可能繁忙）；模型描述直接写在选择器里。
- **深度思考**：`message_r1_button` / `Think`、`message_thinking`、`call_thinking` 等字符串；思考过程与正式回答分离。
- **联网搜索**：`message_searching*`、`merge_tool_search_result(s)`、`Read N web pages`、`Browsed search result`、来源列表；搜索以工具卡片/引用形式出现。
- **文件上传**：`attach_files`、`file_uploading`、`file_token_exceeds`、`default_upload_panel_o_c_r_tip_with_vision`（Instant/Expert 模式对文件只做文本提取的提示）。
- **语音通话**：完整通话状态机（连接、聆听、打断、字幕、结束、评分、每日限额）以及流体光斑 shader。
- **消息操作**：复制、重新生成（可带/不带搜索）、反馈、消息内搜索、分享。
- **图片**：预览、保存、裁剪失败回退原图。
- **视觉语言**：白底、极少装饰、中心内容列、蓝色作为唯一强调色；输入区为圆角胶囊；设置与模型选择用底部面板；深色模式由 DayNight 主题支持。

Lumen 采用了这些**结构性经验**：单一强调色、宽留白、居中对话列、胶囊输入、思考/联网开关、工具卡片、来源引用、移动端抽屉。没有复用其 Logo、插画、文案或布局文件。

## 3. 性能与工程优化观察

- **启动**：baseline profile 说明对首屏方法做了 AOT 预热；Lumen 在 Web 端用 splash 遮罩等待首帧，Android 端用 native splash，避免“白屏假死”。
- **包体**：仅 arm64 原生库，说明主 APK 面向现代设备；Lumen 的 Flutter APK 由 Flutter 引擎按 ABI 打包，可在发布时配置 split-per-abi。
- **渲染**：Compose + 自定义 shader；Lumen 使用 Flutter 的 Impeller/Skia（Web 为 CanvasKit），对话流式渲染采用节流通知（约 28 ms）与 Markdown 增量重绘。
- **存储**：WCDB + MMKV 的组合适合大量消息与高频键值；Lumen 用 Sembast（纯 Dart、跨 Android/Web）换取零原生依赖与 Web 可运行，个人规模足够。
- **公式**：jlatexmath 离线渲染；Lumen 用 `flutter_math_fork`，同样离线，支持行内/块级公式。
- **语音**：LiteAV/ffmpeg 说明语音通话是重投入能力；Lumen 当前聚焦文本 Agent，未实现语音，避免引入大体积 RTC SDK。

## 4. 思考强度的实现参考（RikkaHub + 官方文档）

RikkaHub 用一个 7 档 `ReasoningLevel` 统一 UI，再按 provider/host 转成原生参数。Lumen 采用同样的思路，但在字段上做了容错：

| 平台 | 请求字段 | Lumen 行为 |
|---|---|---|
| OpenAI / 自定义 / OpenCode | `reasoning_effort` | 关闭→`none`，自动→不发送，xhigh/max→`high`；400 时去掉重试 |
| DeepSeek | `thinking.type` + `reasoning_effort` | 关闭→disabled；自动→enabled；低→low；中/高→high；xhigh/max 原样；400 时去掉重试 |
| 智谱 GLM | `thinking.type` | 只区分开/关；强度档位折叠为 enabled |
| Kimi / Moonshot | `thinking.type` (+`keep`) | 只区分开/关；K2.6 系列开启时附带 `keep="all"`，K2.5 不带 |
| 阿里百炼 / DashScope | `reasoning_effort` | 自动不发送；关闭→none；xhigh/max→high |
| MiniMax | `reasoning_effort` | 自动不发送；其余按 low/medium/high/none 映射 |
| OpenRouter | `reasoning` 对象 | 关闭→`{effort:none}`；自动→`{enabled:true}`；其余→`{effort:...}` |
| Anthropic | `thinking` + `output_config.effort` | 关闭→disabled；自动→adaptive + summarized；其余→adaptive + effort；旧模型 400 时回退 `enabled + budget_tokens` |
| Gemini | `thinkingConfig` | Gemini 3/4 用 `thinkingLevel`；2.5 用 `thinkingBudget`；Pro 无法完全关闭时保持自动；`includeThoughts` 开启 |

这些映射集中在一个纯函数文件中，单元测试直接断言 payload，不依赖真实网络。

## 5. Lumen 的取舍

| 决策 | 原因 |
|---|---|
| Flutter（Android + Web） | 同一套 UI/业务代码可跑手机与桌面浏览器；方便快速做视觉验收 |
| 本地优先 Sembast | 无原生依赖、Android 文件 / Web IndexedDB 同构；个人记忆库规模足够 |
| Key 独立安全存储 | Key 不进入会话数据库；Web 退化为浏览器本地存储并明确提示 |
| 适配器分层 | OpenAI/Anthropic/Gemini 协议差异在客户端内消化；URL/模型/参数互不污染 |
| 统一工具循环 | 搜索、记忆、MCP 都是 tool；UI 只关心 ToolCall 状态与结果 |
| 不做账号/云同步 | 降低复杂度，先保证“数据在本机”和可导出 |
| 不做语音 | 避免 RTC/ffmpeg 大依赖；先把文本 Agent 核心做扎实 |

## 6. 已知差距

- DeepSeek 的双模型 Instant/Expert、账号体系、跨设备同步、语音通话、文件 OCR、消息内搜索、分享链接等，Lumen 未逐项复刻；Lumen 用“多厂商 + 统一模型列表 + 浏览器/文件工具”提供另一种解法。
- DeepSeek 的 UI 细节（具体间距、动画时长、图标）无法仅从资源完全还原；Lumen 采用同一设计语言但独立实现。
- 思考参数会随厂商 API 演进而变化；Lumen 需要持续更新映射与模型能力推断，当前以 2026-10 的 RikkaHub/官方文档为基线。

## 7. 合规说明

- 本分析仅用于学习架构与交互设计；未提取、复制或再分发 DeepSeek 的源代码、图像、字体、文案或商标资源。
- Lumen 中的厂商 Logo 用于标识用户配置的服务提供方，属于指示性使用；商标归各自权利人所有。
- 若将 Lumen 对外分发，请自行确认各厂商 API 条款、模型输出内容政策、Logo 使用规范与当地法律要求。
