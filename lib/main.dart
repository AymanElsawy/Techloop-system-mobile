import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/app_scope.dart';
import 'core/offline.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'features/auth/change_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/offline/offline_banner.dart';
import 'features/shell/shell.dart';

/// Light / dark / follow the device; changed from the drawer.
final themeMode = ValueNotifier(ThemeMode.system);

final _navigator = GlobalKey<NavigatorState>();

Future<void> main() async {
  // Keep the native splash up until we know where to go: home right away, login after 1s.
  FlutterNativeSplash.preserve(
    widgetsBinding: WidgetsFlutterBinding.ensureInitialized(),
  );
  await initializeDateFormatting('ar_EG');
  final session = Session(await OfflineStore.open());
  session.restore().whenComplete(
    () => Future.delayed(
      session.user == null ? const Duration(seconds: 1) : Duration.zero,
      FlutterNativeSplash.remove,
    ),
  );
  runApp(
    AppScope(
      session: session,
      child: TechloopApp(session: session),
    ),
  );
}

class TechloopApp extends StatelessWidget {
  const TechloopApp({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Techloop',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar', 'EG'),
        supportedLocales: const [Locale('ar', 'EG')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        navigatorKey: _navigator,
        builder: (context, child) => OfflineBanner(
          session: session,
          navigator: _navigator,
          child: child!,
        ),
        home: ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            if (session.restoring)
              return const SizedBox.shrink(); // native splash still covers it
            final user = session.user;
            if (user == null) return LoginScreen(session: session);
            if (user.mustChangePassword)
              return ChangePasswordScreen(session: session);
            return Shell(session: session);
          },
        ),
      ),
    );
  }
}
