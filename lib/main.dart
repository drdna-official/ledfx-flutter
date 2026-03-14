import 'package:flutter/material.dart';
import 'package:ledfx/background.dart' as bg;
import 'package:ledfx/src/platform/audio_bridge.dart';
import 'package:ledfx/worker.dart';
import 'package:ledfx/ui/adaptive_layout.dart';

@pragma('vm:entry-point')
void backgroundAudioProcessing() => bg.backgroundAudioProcessing();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AudioBridge.instance.setupBackgroundExecution(backgroundAudioProcessing);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Visualizer',
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Center(
          child: FutureBuilder(
            future: LEDFxWorker.instance.init(),
            builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Column(children: [CircularProgressIndicator(), Text('Connecting to Background Isolate')]),
                );
              } else if (snapshot.hasError) {
                return Center(
                  child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                );
              } else if (snapshot.connectionState == ConnectionState.done) {
                return AdaptiveNavigationLayout();
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}
