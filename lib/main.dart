import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/ui.dart';
import 'package:provider/provider.dart';

import 'state/bot_state.dart';
import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  runApp(const DerivBotApp());
}

class DerivBotApp extends StatelessWidget {
  const DerivBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BotState(),
      child: MaterialApp(
        title: 'Deriv AI Bot',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.redAccent,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const WithForegroundTask(child: HomeScreen()),
      ),
    );
  }
}
