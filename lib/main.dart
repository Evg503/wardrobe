import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/app_state.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = await AppState.create();
  runApp(WardrobeApp(appState: appState));
}

class WardrobeApp extends StatelessWidget {
  final AppState appState;

  const WardrobeApp({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: appState,
      child: MaterialApp(
        title: 'Wardrobe',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: appState.onboardingCompleted
            ? const HomeScreen()
            : _OnboardingWrapper(appState: appState),
      ),
    );
  }
}

/// Обёртка онбординга: после завершения переключает на HomeScreen.
class _OnboardingWrapper extends StatelessWidget {
  final AppState appState;

  const _OnboardingWrapper({required this.appState});

  @override
  Widget build(BuildContext context) {
    return OnboardingScreen(
      onComplete: () async {
        await appState.completeOnboarding();
        if (context.mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const HomeScreen(),
              transitionsBuilder: (_, animation, __, child) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              transitionDuration: const Duration(milliseconds: 400),
            ),
          );
        }
      },
    );
  }
}
