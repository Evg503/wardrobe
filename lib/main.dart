import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
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
        home: const HomeScreen(),
      ),
    );
  }
}
