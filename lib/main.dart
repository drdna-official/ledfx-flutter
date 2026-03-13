import 'package:flutter/material.dart';
import 'package:ledfx/background.dart' as bg;
import 'package:ledfx/src/platform/audio_bridge.dart';
import 'package:ledfx/src/worker.dart';
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
  late LEDFxWorker ledfxWorker;
  @override
  void initState() {
    super.initState();
    ledfxWorker = LEDFxWorker();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Visualizer',
      theme: ThemeData.dark(),
      // home: const SettingsPage(),
      home: Scaffold(
        body: Center(
          child: FutureBuilder(
            future: ledfxWorker.init(),
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
                return AdaptiveNavigationLayout(ledfxWorker: ledfxWorker);

                // Center(
                //   child:

                //   CustomScrollView(
                //     slivers: <Widget>[
                //       SliverPersistentHeader(
                //         pinned: true, // Make it sticky/pinned
                //         delegate: AutoSizeStickyHeaderDelegate(
                //           // The sticky header will always be this height
                //           minHeight: fixedHeaderHeight,
                //           // And will not expand beyond this height
                //           maxHeight: fixedHeaderHeight,
                //           child: _buildStickyContent(),
                //         ),
                //       ),
                //       SliverList(
                //         delegate: SliverChildBuilderDelegate(
                //           (BuildContext context, int index) {
                //             // Build a ListTile for each item
                //             return ListTile(
                //               leading: CircleAvatar(
                //                 child: Text('${index + 1}'),
                //               ),
                //               title: Text('List Item $index'),
                //               subtitle: const Text(
                //                 'This section is scrollable.',
                //               ),
                //             );
                //           },
                //           // The total number of list items to generate
                //           childCount: 50,
                //         ),
                //       ),
                //     ],
                //   ),

                // );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}
