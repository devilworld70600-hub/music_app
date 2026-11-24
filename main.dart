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
    // pause par bhi notification dikhti rahe (Spotify jaisa)
    androidNotificationOngoing: false,
    androidStopForegroundOnPause: false,
    androidNotificationIcon: 'drawable/ic_stat_music',
    androidShowNotificationBadge: true,
    notificationColor: const Color(0xFFE53935),
  );
  Library.i.load();
  runApp(const MusicApp());
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Universal Music',
        scaffoldMessengerKey: messengerKey,
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

// Animated splash: logo pop + glow + naam slide, phir zoom-fade ke saath app khulti hai
class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  bool _splash = true;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      if (mounted) setState(() => _splash = false);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        const Shell(),
        if (_splash) Positioned.fill(child: _SplashView(_c)),
      ]);
}

class _SplashView extends StatelessWidget {
  final Animation<double> t;
  const _SplashView(this.t);

  static double _seg(double v, double a, double b) => ((v - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: t,
        builder: (_, __) {
          final v = t.value;
          // 0.00-0.45 logo pop, 0.25-0.60 naam, 0.80-1.00 exit
          final pop = Curves.elasticOut.transform(_seg(v, 0.0, 0.45));
          final fade = Curves.easeOut.transform(_seg(v, 0.0, 0.2));
          final glow = _seg(v, 0.1, 0.7);
          final name = Curves.easeOutCubic.transform(_seg(v, 0.25, 0.6));
          final exit = Curves.easeInCubic.transform(_seg(v, 0.8, 1.0));
          return Opacity(
            opacity: 1 - exit,
            child: Transform.scale(
              scale: 1 + exit * 0.6,
              child: Material(
                color: const Color(0xFF080605),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Opacity(
                      opacity: fade,
                      child: Transform.scale(
                        scale: 0.3 + 0.7 * pop,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE53935).withOpacity(0.55 * glow),
                                blurRadius: 20 + 40 * glow,
                                spreadRadius: 2 + 8 * glow,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.asset('assets/icon.png', width: 96, height: 96),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Opacity(
                      opacity: name,
                      child: Transform.translate(
                        offset: Offset(0, 16 * (1 - name)),
                        child: const Text('Universal Music',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                                color: Colors.white)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int tab = 0;
  final pages = const [HomeScreen(), SearchScreen(), LibraryScreen()];
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // splash khatam hone ke baad permission maango, warna dialog splash ke upar dab jata hai
    Future.delayed(const Duration(milliseconds: 2700), _askNotification);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // settings se wapas aane par dobara check
    if (state == AppLifecycleState.resumed && _asked) {
      Permission.notification.status.then((st) {
        if (st.isGranted && mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      });
    }
  }

  Future<void> _askNotification() async {
    _asked = true;
    var st = await Permission.notification.status;
    if (!st.isGranted) st = await Permission.notification.request();
    if (!mounted) return;
    if (!st.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: const Text('Turn on notifications to control music from the lock screen'),
        action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
      ));
    }
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
