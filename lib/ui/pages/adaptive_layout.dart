import 'package:flutter/material.dart';
import 'package:ledfx/ui/pages/device_page.dart';
import 'package:ledfx/ui/pages/home_page.dart';
import 'package:ledfx/ui/pages/settings_page.dart';
import 'package:ledfx/ui/pages/virtual_page.dart';
import 'package:ledfx/ui/visualizer/visualizer_painter.dart';
import 'package:ledfx/worker.dart';

// Recommended Material Design Breakpoints
const double kMediumBreakpoint = 600.0;
const double kExpandedBreakpoint = 840.0;

enum AdaptiveLayout { compact, medium, expanded }

// class AdaptiveNavigationLayout extends StatelessWidget {
//   const AdaptiveNavigationLayout({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return LayoutBuilder(
//       builder: (context, constraints) {
//         final double width = constraints.maxWidth;

//         if (width < kMediumBreakpoint) {
//           // 1. COMPACT (Mobile) View: Uses Drawer and shows the hamburger icon
//           return CompactLayout();
//         } else if (width < kExpandedBreakpoint) {
//           // 2. MEDIUM (Tablet) View: Uses Navigation Rail, NO Drawer needed.
//           return Scaffold(
//             appBar: AppBar(
//               title: const Text('Medium View (Nav Rail)'),
//               // Since 'drawer' is null, NO hamburger icon is shown
//             ),
//             // Explicitly set drawer to null
//             drawer: null,
//             body: MediumLayout(),
//           );
//         } else {
//           // 3. EXPANDED (Desktop) View: Uses Permanent Sidebar, NO Drawer needed.
//           return Scaffold(
//             appBar: AppBar(
//               title: const Text('Expanded View (Sidebar)'),
//               // Since 'drawer' is null, NO hamburger icon is shown
//             ),
//             // Explicitly set drawer to null
//             drawer: null,
//             body: ExpandedLayout(),
//           );
//         }
//       },
//     );
//   }
// }

class AdaptiveNavigationLayout extends StatefulWidget {
  const AdaptiveNavigationLayout({super.key});

  @override
  State<AdaptiveNavigationLayout> createState() => _AdaptiveNavigationLayoutState();
}

class _AdaptiveNavigationLayoutState extends State<AdaptiveNavigationLayout> {
  final LEDFxWorker ledfxWorker = LEDFxWorker.instance;
  int _selectedIndex = 1;
  bool playing = false;

  final _homeKey = GlobalKey(debugLabel: "home_page");
  final _deviceKey = GlobalKey(debugLabel: "device_page");
  final _virtualKey = GlobalKey(debugLabel: "virtual_page");
  final _settingsKey = GlobalKey(debugLabel: "settings_page");

  @override
  void initState() {
    super.initState();
    playing = ledfxWorker.isAudioCapturing.value;

    ledfxWorker.infoSnackText.addListener(_infoSnackListener);
    ledfxWorker.isAudioCapturing.addListener(_audioCapturingListener);
  }

  @override
  void dispose() {
    ledfxWorker.infoSnackText.removeListener(_infoSnackListener);
    ledfxWorker.isAudioCapturing.removeListener(_audioCapturingListener);
    super.dispose();
  }

  void _infoSnackListener() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ledfxWorker.infoSnackText.value)));
    }
  }

  void _audioCapturingListener() {
    if (mounted) {
      setState(() => playing = ledfxWorker.isAudioCapturing.value);
    }
  }

  void setIndex(int index) {
    setState(() => _selectedIndex = index);
  }

  AdaptiveLayout getLayout() {
    final double width = MediaQuery.of(context).size.width;
    if (width < kMediumBreakpoint) {
      return AdaptiveLayout.compact;
    } else if (width < kExpandedBreakpoint) {
      return AdaptiveLayout.medium;
    } else {
      return AdaptiveLayout.expanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLayout = getLayout();
    final List<Widget> pages = [
      HomePage(key: _homeKey, layout: currentLayout),
      DevicePage(key: _deviceKey, layout: currentLayout),
      VirtualStripPage(key: _virtualKey, layout: currentLayout),
      SettingsPage(key: _settingsKey, layout: currentLayout),
    ];

    Widget body = IndexedStack(index: _selectedIndex, children: pages);

    body = currentLayout != AdaptiveLayout.compact
        ? Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                extended: currentLayout == AdaptiveLayout.expanded,
                onDestinationSelected: (index) => setState(() => _selectedIndex = index),
                labelType: currentLayout == AdaptiveLayout.expanded
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,

                destinations: const [
                  NavigationRailDestination(icon: Icon(Icons.home_rounded), label: Text('Dashboard')),
                  NavigationRailDestination(icon: Icon(Icons.devices_other_rounded), label: Text('Devices')),
                  NavigationRailDestination(icon: Icon(Icons.insights_rounded), label: Text('Virtuals')),
                  NavigationRailDestination(icon: Icon(Icons.settings_rounded), label: Text('Settings')),
                ],
              ),
              Expanded(child: body),
            ],
          )
        : body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LEDFx'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        // actions: [
        //   IconButton(onPressed: () => ledfxWorker.requestState(), icon: Icon(Icons.refresh_rounded)),
        //   SizedBox(width: 16),
        // ],
      ),
      // drawer: currentLayout == AdaptiveLayout.compact ? const AppNavigationDrawer() : null,
      body: Stack(
        children: [
          body,
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: SizedBox(
                height: 50,
                child: RepaintBoundary(
                  child: ValueListenableBuilder(
                    valueListenable: ledfxWorker.getDeviceRgbNotifier("dummyViz"),
                    builder: (context, value, child) {
                      return CustomPaint(
                        painter: BarVisualizerPainter(
                          values: value,
                          ledCount: 300,
                          valueType: BarVisualizerValueType.rgbBars,
                          alpha: 0.5,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: currentLayout != AdaptiveLayout.compact
          ? BottomAppBar(shape: CircularNotchedRectangle(), notchMargin: 8.0)
          : BottomAppBar(
              shape: CircularNotchedRectangle(),
              notchMargin: 8.0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    onPressed: () => setIndex(0),
                    isSelected: _selectedIndex == 0,
                    icon: Icon(Icons.home_rounded),
                    selectedIcon: Icon(Icons.home_rounded, color: Theme.of(context).colorScheme.primary),
                  ),
                  IconButton(
                    onPressed: () => setIndex(1),
                    isSelected: _selectedIndex == 1,
                    icon: Icon(Icons.devices_other_rounded),
                    selectedIcon: Icon(Icons.devices_other_rounded, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 40),

                  IconButton(
                    onPressed: () => setIndex(2),
                    isSelected: _selectedIndex == 2,
                    icon: Icon(Icons.insights_rounded),
                    selectedIcon: Icon(Icons.insights_rounded, color: Theme.of(context).colorScheme.primary),
                  ),

                  IconButton(
                    onPressed: () => setIndex(3),
                    isSelected: _selectedIndex == 3,
                    icon: Icon(Icons.settings_rounded),
                    selectedIcon: Icon(Icons.settings_rounded, color: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        heroTag: "play_pause_fab",
        shape: CircleBorder(),
        onPressed: () async {
          if (playing) {
            await ledfxWorker.stopAudioCapture();
          } else {
            await ledfxWorker.startAudioCapture();
          }
        },
        child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
      ),
    );
  }
}
