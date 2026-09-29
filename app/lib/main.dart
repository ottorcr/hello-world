import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'data/models.dart';
import 'data/repository.dart';
import 'firebase_options.dart';
import 'ui/auth_screens.dart';
import 'ui/home_shell.dart';
import 'widget_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await WidgetSync.init();
  // Never leave someone's feed on the home screen after they sign out.
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user == null) WidgetSync.clear();
  });
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
      home: const AuthGate(),
    );
  }
}

/// Signed out → sign in. Unverified email → verify. No profile → set up.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data;
        if (user == null) return const SignInScreen();
        if (!user.emailVerified) return VerifyEmailScreen(user: user);
        return _ProfileGate(
          key: ValueKey(user.uid),
          repo: Repository(user.uid),
        );
      },
    );
  }
}

class _ProfileGate extends StatelessWidget {
  const _ProfileGate({super.key, required this.repo});

  final Repository repo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Profile?>(
      stream: repo.watchProfile(),
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = snap.data;
        if (profile == null) return ProfileSetupScreen(repo: repo);
        return HomeShell(repo: repo, profile: profile);
      },
    );
  }
}
