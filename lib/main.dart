import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:ledfx/background.dart' as bg;
import 'package:ledfx/platform_interface/audio_bridge.dart';
import 'package:ledfx/worker.dart';
import 'package:ledfx/ui/pages/adaptive_layout.dart';

@pragma('vm:entry-point')
void backgroundAudioProcessing({RootIsolateToken? token}) => bg.backgroundAudioProcessing(token: token);

void main(List<String> args) async {
  print("[Dart Main] Args: $args");
  WidgetsFlutterBinding.ensureInitialized();
  AudioBridge.instance.registerNativeListener();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  if (Platform.isWindows || Platform.isLinux) {
    print("[Dart Main] Spawning background isolate for ${Platform.operatingSystem}");
    final rootToken = RootIsolateToken.instance!;
    Isolate.spawn((token) => backgroundAudioProcessing(token: token), rootToken);

    // Forward events to background isolate
    AudioBridge.instance.events.listen((event) {
      final bgPort = IsolateNameServer.lookupPortByName("ledfx_bg_port");
      if (bgPort != null) {
        bgPort.send({"cmd": "bridge_event", "payload": event});
      }
    });
  } else {
    // Android still uses native foreground service / background engine for now
    await AudioBridge.instance.setupBackgroundExecution(backgroundAudioProcessing);
  }

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
    // TODO: REMOVE WHEN variable refresh rate is in flutter already
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      if (Platform.isAndroid) {
        await FlutterDisplayMode.setHighRefreshRate();
      }
    });
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
