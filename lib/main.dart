import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ledfx/background.dart' as bg;
import 'package:ledfx/platform_interface/audio_bridge.dart';
import 'package:ledfx/worker.dart';
import 'package:ledfx/ui/pages/adaptive_layout.dart';

@pragma('vm:entry-point')
void backgroundAudioProcessing() => bg.backgroundAudioProcessing();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await AudioBridge.instance.setupBackgroundExecution(backgroundAudioProcessing);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<bool> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = LEDFxWorker.instance.init();
  }

  @override
  void dispose() {
    LEDFxWorker.instance.dispose();
    super.dispose();
  }

  final colorScheme = ColorScheme.fromSeed(seedColor: Colors.amber, brightness: Brightness.dark);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LEDFx - Audio Visualizer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        // Global BottomAppBar Theme
        bottomAppBarTheme: BottomAppBarThemeData(color: colorScheme.surfaceContainer),
        // Global NavigationRail Theme
        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: colorScheme.surfaceContainer,
          selectedLabelTextStyle: TextStyle(fontStyle: FontStyle.italic),
          unselectedLabelTextStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ),
      home: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
        child: Scaffold(
          body: Center(
            child: FutureBuilder(
              future: _initFuture,
              builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Scaffold(
                    appBar: AppBar(
                      title: Text('LEDFx'),
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    ),

                    body: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [CircularProgressIndicator(), Text('Initializing Engine...')],
                      ),
                    ),
                  );
                } else if (snapshot.hasError) {
                  return Scaffold(
                    appBar: AppBar(title: Text('LEDFx')),
                    body: Center(
                      child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                    ),
                  );
                } else if (snapshot.connectionState == ConnectionState.done) {
                  if (snapshot.data == true) {
                    return AdaptiveNavigationLayout();
                  } else {
                    return Scaffold(
                      appBar: AppBar(
                        title: Text('LEDFx'),
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      ),
                      body: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Failed to initialize Engine', style: const TextStyle(color: Colors.red)),
                            ElevatedButton(
                              onPressed: () {
                                _initFuture = LEDFxWorker.instance.init();
                                setState(() {});
                              },
                              child: Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
  }
}
