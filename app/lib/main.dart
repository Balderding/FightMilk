import 'dart:io';

import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import 'data/recovery.dart';
import 'services/crash_log.dart';
import 'ui/recovery_screen.dart';

import 'ui/app_state.dart';
import 'domain/plan_share.dart' show linkPrefix, readSharedPlan;
import 'ui/history_screen.dart';
import 'ui/plan_receive.dart';
import 'ui/plan_screen.dart';
import 'ui/progress_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/shortcuts.dart';
import 'ui/setup_screen.dart';
import 'ui/theme.dart';
import 'ui/today_screen.dart';
import 'ui/widgets.dart' show toast;
import 'ui/import_screen.dart';
import 'domain/import.dart' show looksLikeCsv, readImport;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // the local crash log (F430): only error types and where they happened, on this phone
  try {
    CrashLog.install(CrashLog(File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}crash_log.json')));
  } catch (_) {}
  // F413: llama.cpp is native code, so Flutter does not list it by itself
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['llama.cpp (on-phone AI engine)'], await rootBundle.loadString('assets/licenses/llama.cpp.txt'));
    yield const LicenseEntryWithLineBreaks(['LFM models (Liquid AI)'], 'The on-phone LFM models are not part of the app. They are made by Liquid AI under the LFM Open License and are downloaded from Hugging Face only when you ask; their licence is shown on the model page there.');
  });
  AppState.clearShared(olderThan: const Duration(hours: 1)); // files shared over an hour ago are no longer needed (review 5, P1-2)
  runApp(const WorkoutApp());
}

class WorkoutApp extends StatefulWidget {
  /// How the app's data is opened (tests give their own).
  final Future<AppState> Function() loader;
  const WorkoutApp({super.key, this.loader = AppState.load});
  @override
  State<WorkoutApp> createState() => _WorkoutAppState();
}

class _WorkoutAppState extends State<WorkoutApp> {
  // held here so "Try again" can start it again (the recovery screen, F431)
  late Future<AppState> _load = _start();
  bool _forced = false;

  Future<AppState> _start() async {
    try {
      // a DEBUG build started with --dart-define=FM_FORCE_RECOVERY=true shows the recovery screen
      // on the real data file once, to check "Save a copy" on a phone; release builds never do
      if (kDebugMode && const bool.fromEnvironment('FM_FORCE_RECOVERY') && !_forced) {
        _forced = true;
        throw StartFailure(p.join(await getDatabasesPath(), 'workout.db'), Exception('started with FM_FORCE_RECOVERY for a check'));
      }
      return await widget.loader();
    } catch (e, st) {
      await CrashLog.current?.record(e is StartFailure ? e.error : e, st);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FightMilk',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: FutureBuilder<AppState>(
          future: _load,
          builder: (c, snap) {
            if (snap.hasError) {
              final e = snap.error;
              return RecoveryScreen(
                key: ObjectKey(e),
                failure: e is StartFailure ? e : StartFailure('', e ?? 'unknown'),
                onRetry: () {
                  final next = _start();
                  setState(() {
                    _load = next;
                  });
                },
              );
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

  static const _incoming = MethodChannel('workout/incoming');
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIncoming();
      widget.s.dailyBackup().ignore();
    });
  }

  /// A plan someone sent opens here: checked and shown before anything is saved (batch 20).
  /// A fightmilk:// link the app doesn't know opens nothing.
  Future<void> _checkIncoming() async {
    if (_reading || widget.s.plan == null) return; // after setup; Android keeps the intent until then
    _reading = true;
    try {
      final got = await _incoming.invokeMapMethod<String, String>('take');
      if (got == null || !mounted) return;
      final kind = got['kind'] ?? '', text = got['text'] ?? '', type = got['type'] ?? '';
      final csvType = type.contains('csv');
      if (kind == 'too_big') {
        toast(context, csvType ? 'That file is too big to import (over 8 MB).' : 'That file is too big to be a plan (over 1 MB).');
        return;
      }
      if (kind == 'too_slow') {
        toast(context, 'That file took too long to read. Try saving it to the phone first.');
        return;
      }
      if (kind != 'ok' || text.isEmpty) return;
      if (type == 'shortcut') {
        // an app shortcut or the Quick Settings tile (batch 23): only opens a screen
        if (shortcutPlaces.contains(text)) await openShortcut(context, widget.s, text, (i) => setState(() => tab = i));
        return;
      }
      // a link (or an NFC sticker) that only opens a screen (F354, F356)
      final link = readLink(text);
      if (link != null) {
        await openShortcut(context, widget.s, link.go, (i) => setState(() => tab = i), kg: link.kg, fromLink: true, odd: link.odd);
        return;
      }
      if (text.startsWith('fightmilk:') && !text.startsWith(linkPrefix)) return;
      // a history file goes to the import, a plan to the plan reader (review 6 P2-5): by its type,
      // else by its header; a table the importer can't read but the plan reader can is a plan
      if (csvType || looksLikeCsv(text)) {
        final r = readImport(text, appUnit: widget.s.unit);
        if (r.ok || !readSharedPlan(text, widget.s.lib).ok) {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ImportScreen(s: widget.s, text: text)));
          return;
        }
      }
      await receivePlan(context, widget.s, text);
    } catch (_) {
      // no channel (tests, desktop): nothing to read
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) widget.s.appPaused();
    if (state == AppLifecycleState.resumed) {
      widget.s.appResumed();
      _checkIncoming();
      widget.s.dailyBackup().ignore(); // a day old: the daily automatic backup (F339)
    }
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
