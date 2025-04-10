import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'services/firebase_service.dart';
import 'services/auth_service.dart';
import 'login_page.dart';
import 'home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider(create: (_) => FirebaseService()),
      ],
      child: const BanglaLitApp(),
    ),
  );
}

class BanglaLitApp extends StatelessWidget {
  const BanglaLitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BanglaLit',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        fontFamily: 'Hind Siliguri', // A font that supports Bangla
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: FutureBuilder(
        future:
            Provider.of<AuthService>(context, listen: false).initializeUser(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return Consumer<AuthService>(
            builder: (context, authService, _) {
              return authService.currentUser != null
                  ? const HomePage()
                  : const LoginPage();
            },
          );
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
