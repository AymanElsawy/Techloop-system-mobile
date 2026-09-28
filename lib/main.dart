import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'core/app_scope.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/shell.dart';

/// Light / dark / follow the device; changed from the drawer.
final themeMode = ValueNotifier(ThemeMode.system);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  DateFormat.useNativeDigitsByDefaultFor('ar', false); // Western digits, like the web app
  final session = Session()..restore();
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
        title: 'Veterinary Pharma',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        home: ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            if (session.restoring) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            return session.user == null ? LoginScreen(session: session) : Shell(session: session);
          },
        ),
      ),
    );
  }
}
