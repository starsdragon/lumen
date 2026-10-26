import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'services/controllers.dart';
import 'ui/app_shell.dart';
import 'ui/onboarding.dart';

class LumenApp extends StatelessWidget {
  const LumenApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    return MaterialApp(
      title: 'Lumen',
      debugShowCheckedModeBanner: false,
      theme: buildLumenTheme(brightness: Brightness.light),
      darkTheme: buildLumenTheme(brightness: Brightness.dark),
      themeMode: settings.themeMode,
      themeAnimationDuration: const Duration(milliseconds: 220),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      scrollBehavior: const _LumenScrollBehavior(),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
            systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          ),
          child: MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(settings.textScale.clamp(0.85, 1.3)),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: settings.onboardingDone
            ? const AppShell(key: ValueKey('shell'))
            : const OnboardingScreen(key: ValueKey('onboarding')),
      ),
    );
  }
}

class _LumenScrollBehavior extends MaterialScrollBehavior {
  const _LumenScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
