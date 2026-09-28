import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'home_page.dart';
import 'widget_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await WidgetSync.init(app.options.projectId);
  runApp(const RandomThoughtsApp());
}

class RandomThoughtsApp extends StatelessWidget {
  const RandomThoughtsApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF7C4DFF);
    return MaterialApp(
      title: 'Random Thoughts',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}
