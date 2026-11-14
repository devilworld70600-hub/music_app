import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core.dart';
import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.music_app.audio',
    androidNotificationChannelName: 'Music playback',
    androidNotificationOngoing: true,
  );
  Library.i.load();
  runApp(const MusicApp());
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Universal Music',
        debugShowCheckedModeBanner: false,
        // phone ka bada font setting ho to bhi app ke text bade na dikhen
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.8,
          maxScaleFactor: 0.95,
          child: child!,
        ),
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Inter',
          visualDensity: VisualDensity.compact,
          scaffoldBackgroundColor: const Color(0xFF121212),
          colorScheme: const ColorScheme.dark(primary: kAccent),
          navigationBarTheme: NavigationBarThemeData(
            height: 60,
            backgroundColor: const Color(0xFF121212),
            indicatorColor: Colors.transparent,
            iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
                color: s.contains(WidgetState.selected) ? Colors.white : Colors.white54)),
            labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
                fontSize: 11,
                color: s.contains(WidgetState.selected) ? Colors.white : Colors.white54)),
          ),
        ),
        home: const Root(),
      );
}

// Chhota branded splash: logo + naam. App piche load hoti rehti hai.
class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  bool _splash = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _splash = false);
    });
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        const Shell(),
        if (_splash) const Positioned.fill(child: _SplashView()),
      ]);
}

class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF080605),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset('assets/icon.png', width: 88, height: 88),
            ),
            const SizedBox(height: 14),
            const Text('Universal Music',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
          ]),
        ),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  final pages = const [HomeScreen(), SearchScreen(), LibraryScreen()];

  @override
  void initState() {
    super.initState();
    Permission.notification.request(); // Android 13+ pe notification ke liye zaroori
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: tab, children: pages),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
                NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Your Library'),
              ],
            ),
          ],
        ),
      );
}
