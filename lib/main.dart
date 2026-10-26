import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/database.dart';
import 'services/controllers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final database = await AppDatabase.open();
    final repository = AppRepository(database, SecretStore());
    await repository.initialize();

    final settings = SettingsController(repository);
    final providers = ProvidersController(repository);
    final conversations = ConversationsController(repository);
    final memories = MemoriesController(repository);
    final mcp = McpController(repository);

    await Future.wait([
      settings.load(),
      providers.load(),
      conversations.load(),
      memories.load(),
      mcp.load(),
    ]);

    runApp(
      MultiProvider(
        providers: [
          Provider<AppRepository>.value(value: repository),
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<ProvidersController>.value(value: providers),
          ChangeNotifierProvider<ConversationsController>.value(value: conversations),
          ChangeNotifierProvider<MemoriesController>.value(value: memories),
          ChangeNotifierProvider<McpController>.value(value: mcp),
        ],
        child: const LumenApp(),
      ),
    );
  } catch (error, stack) {
    runApp(_StartupErrorApp(error: error, stack: stack));
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error, required this.stack});

  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFE5484D), size: 40),
                  const SizedBox(height: 16),
                  const Text(
                    'Lumen 启动失败',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text('$error', style: const TextStyle(height: 1.6)),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: const Text('查看错误堆栈'),
                    children: [
                      SelectableText('$stack', style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
