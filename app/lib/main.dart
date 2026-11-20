import 'package:flutter/material.dart';

import 'ui/app_state.dart';
import 'ui/history_screen.dart';
import 'ui/plan_screen.dart';
import 'ui/progress_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/setup_screen.dart';
import 'ui/theme.dart';
import 'ui/today_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WorkoutApp());
}

class WorkoutApp extends StatefulWidget {
  const WorkoutApp({super.key});
  @override
  State<WorkoutApp> createState() => _WorkoutAppState();
}

class _WorkoutAppState extends State<WorkoutApp> {
  late final Future<AppState> _load = AppState.load();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FightMilk',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: FutureBuilder<AppState>(
          future: _load,
          builder: (c, snap) {
            if (snap.hasError) {
              return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not start: ${snap.error}'))));
            }
            if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            return Home(s: snap.data!);
          },
        ),
      );
}

class Home extends StatefulWidget {
  final AppState s;
  const Home({super.key, required this.s});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) widget.s.appPaused();
    if (state == AppLifecycleState.resumed) widget.s.appResumed();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.s,
        builder: (c, _) {
          final s = widget.s;
          if (s.profile == null || s.plan == null) return SetupScreen(s: s, firstRun: true);
          final pages = [TodayScreen(s: s), PlanScreen(s: s), HistoryScreen(s: s), ProgressScreen(s: s), SettingsScreen(s: s)];
          return Scaffold(
            body: pages[tab],
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
                NavigationDestination(icon: Icon(Icons.view_list_outlined), selectedIcon: Icon(Icons.view_list), label: 'Plan'),
                NavigationDestination(icon: Icon(Icons.history), label: 'History'),
                NavigationDestination(icon: Icon(Icons.show_chart), label: 'Progress'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
              ],
            ),
          );
        },
      );
}
