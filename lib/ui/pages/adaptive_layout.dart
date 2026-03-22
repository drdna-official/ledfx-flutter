import 'package:flutter/material.dart';
import 'package:ledfx/ui/pages/device_page.dart';
import 'package:ledfx/ui/pages/home_body.dart';
import 'package:ledfx/ui/pages/virtual_page.dart';
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
  int _selectedIndex = 0;
  bool playing = false;

  @override
  void initState() {
    super.initState();
    playing = ledfxWorker.isAudioCapturing.value;
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
    final List<Widget> pages = [DevicePage(layout: currentLayout), VirtualStripPage(layout: currentLayout)];

    ledfxWorker.infoSnackText.addListener(() {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ledfxWorker.infoSnackText.value)));
      }
    });

    ledfxWorker.isAudioCapturing.addListener(() {
      if (mounted) {
        setState(() => playing = ledfxWorker.isAudioCapturing.value);
      }
    });

    final body = IndexedStack(index: _selectedIndex, children: pages);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LEDFx'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(onPressed: () => ledfxWorker.requestState(), icon: Icon(Icons.refresh_rounded)),
          SizedBox(width: 16),
        ],
      ),
      // drawer: currentLayout == AdaptiveLayout.compact ? const AppNavigationDrawer() : null,
      body: currentLayout != AdaptiveLayout.compact
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
                    NavigationRailDestination(icon: Icon(Icons.devices_other_rounded), label: Text('Devices')),
                    NavigationRailDestination(icon: Icon(Icons.insights_rounded), label: Text('Virtual')),
                  ],
                ),
                Expanded(child: body),
              ],
            )
          : body,
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
                    icon: Icon(Icons.devices_other_rounded),
                    selectedIcon: Icon(Icons.devices_other_rounded, color: Theme.of(context).colorScheme.primary),
                  ),
                  IconButton(
                    onPressed: () => setIndex(1),
                    isSelected: _selectedIndex == 1,
                    icon: Icon(Icons.insights_rounded),
                    selectedIcon: Icon(Icons.insights_rounded, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 40),
                  IconButton(
                    onPressed: () => setIndex(0),
                    isSelected: _selectedIndex == 0,
                    icon: Icon(Icons.blur_on_rounded),
                    selectedIcon: Icon(Icons.blur_on_rounded, color: Theme.of(context).colorScheme.primary),
                  ),
                  IconButton(
                    onPressed: () => setIndex(1),
                    isSelected: _selectedIndex == 1,
                    icon: Icon(Icons.settings),
                    selectedIcon: Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
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

class AppNavigationDrawer extends StatelessWidget {
  const AppNavigationDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: const [
          DrawerHeader(
            decoration: BoxDecoration(color: Colors.red),
            child: Text(
              'LEDFx',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(leading: Icon(Icons.devices_other_rounded), title: Text('Devices')),
          ListTile(leading: Icon(Icons.send), title: Text('Sent')),
        ],
      ),
    );
  }
}

class ExpandedLayout extends StatelessWidget {
  const ExpandedLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Permanent Navigation Sidebar (Wider, custom widget)
        SizedBox(
          width: 250, // Dedicated wider space for the sidebar
          child: ListView(
            padding: EdgeInsets.zero,
            children: const [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Permanent Navigation', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              ListTile(leading: Icon(Icons.dashboard), title: Text('Dashboard')),
              ListTile(leading: Icon(Icons.analytics), title: Text('Analytics')),
              ListTile(leading: Icon(Icons.message), title: Text('Messages')),
            ],
          ),
        ),

        const VerticalDivider(thickness: 1, width: 1),

        // Main Content
        Expanded(child: HomeBody(layout: AdaptiveLayout.expanded)),
      ],
    );
  }
}
