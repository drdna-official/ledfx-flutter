import 'package:flutter/material.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/src/virtual.dart';
import 'package:ledfx/ui/pages/adaptive_layout.dart';
import 'package:ledfx/ui/pages/segments_page.dart';
import 'package:ledfx/worker.dart';

class VirtualStripPage extends StatefulWidget {
  const VirtualStripPage({super.key, required this.layout});
  final AdaptiveLayout layout;

  @override
  State<VirtualStripPage> createState() => _VirtualStripPageState();
}

class _VirtualStripPageState extends State<VirtualStripPage> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        final navigator = _navigatorKey.currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
        }
      },
      child: Navigator(
        key: _navigatorKey,
        initialRoute: '/',
        onGenerateRoute: (settings) {
          WidgetBuilder builder;
          switch (settings.name) {
            case '/':
              builder = (context) => VirtualStripList(layout: widget.layout);
              break;
            case '/segments':
              final virtualID = settings.arguments as (String, String);
              builder = (context) => SegmentsPage(virtualID: virtualID.$1, virtualName: virtualID.$2);
              break;
            default:
              throw Exception('Invalid route: ${settings.name}');
          }
          return MaterialPageRoute(builder: builder, settings: settings);
        },
      ),
    );
  }
}

class VirtualStripList extends StatefulWidget {
  const VirtualStripList({super.key, required this.layout});
  final AdaptiveLayout layout;

  @override
  State<VirtualStripList> createState() => _VirtualStripListState();
}

class _VirtualStripListState extends State<VirtualStripList> {
  final LEDFxWorker ledfxWorker = LEDFxWorker.instance;
  final Map<String, bool> _expandedStates = {};

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ValueListenableBuilder(
            valueListenable: ledfxWorker.virtuals,
            builder: (context, virtuals, child) {
              return ListView.separated(
                shrinkWrap: true,
                separatorBuilder: (context, index) => SizedBox(height: 8),
                itemCount: virtuals.length,
                itemBuilder: (context, index) {
                  final v = virtuals[index];
                  final virtualID = v["id"] as String;
                  final virtualConfig = VirtualConfig.fromJson(v["config"] as Map<String, dynamic>);
                  final device = ledfxWorker.devices.value.firstWhere(
                    (e) => e["id"] == virtualConfig.deviceID,
                    orElse: () => {},
                  )["config"];
                  return ExpansionTile(
                    key: ValueKey(virtualID),
                    maintainState: true,
                    initiallyExpanded: _expandedStates[virtualID] ?? false,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _expandedStates[virtualID] = expanded;
                      });
                    },
                    dense: true,
                    childrenPadding: EdgeInsets.all(8.0),
                    collapsedShape: RoundedRectangleBorder(
                      side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    backgroundColor: Colors.black.withValues(alpha: 0.4),
                    collapsedBackgroundColor: Colors.black.withValues(alpha: 0.2),
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Colors.grey.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            spacing: 4.0,
                            children: [
                              Text(virtualConfig.name, style: TextStyle(fontSize: 15)),
                              if (device != null)
                                Chip(
                                  visualDensity: VisualDensity.compact,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(90))),
                                  padding: EdgeInsets.all(0),
                                  backgroundColor: Colors.blue.withValues(alpha: 0.4),
                                  label: Text(device["name"] ?? "error", style: TextStyle(fontSize: 12)),
                                ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: v["active"] ?? false,
                              onChanged: (bool newVal) {
                                ledfxWorker.toggleVirtual(virtualID, newVal);
                              },
                            ),
                            IconButton(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: Text("Remove Virtual Strip"),
                                      content: Text("Are you sure you want to remove this virtual strip?"),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(context);
                                          },
                                          child: Text("Cancel"),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            ledfxWorker.removeVirtual(virtualID);
                                            Navigator.pop(context);
                                          },
                                          child: Text("Remove"),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                              icon: Icon(Icons.delete, color: Colors.red),
                            ),
                          ],
                        ),
                      ],
                    ),

                    children: [
                      // CONTROLS
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("virtual ID: $virtualID"),
                                    Text(
                                      "Active Effect: ${v["activeEffect"] != null ? v["activeEffect"]["name"] : 'None'}",
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pushNamed(
                                        context,
                                        '/segments',
                                        arguments: (virtualID, virtualConfig.name),
                                      );
                                    },
                                    label: Text("Edit Strip"),
                                    icon: Icon(Icons.edit),
                                  ),
                                  SizedBox(height: 4),
                                  DropdownButton<EffectType>(
                                    value: v["activeEffect"] != null
                                        ? EffectType.fromName(v["activeEffect"]["name"])
                                        : null,
                                    items: EffectType.values.where((v) => v != EffectType.unknown).map((effect) {
                                      return DropdownMenuItem<EffectType>(value: effect, child: Text(effect.fullName));
                                    }).toList(),
                                    onChanged: (effect) {
                                      if (effect != null) {
                                        ledfxWorker.setVirtualEffect(
                                          v["id"],
                                          EffectConfig(name: effect.name, type: effect, mirror: true, blur: 3.0),
                                        );
                                      }
                                    },
                                  ),
                                  // ElevatedButton.icon(
                                  //   onPressed: () {
                                  //     ledfxWorker.setVirtualEffect(
                                  //       v["id"],
                                  //       EffectConfig(
                                  //         name: "wavelength",
                                  //         type: EffectType.wavelength,
                                  //         mirror: true,
                                  //         blur: 3.0,
                                  //       ),
                                  //     );
                                  //   },
                                  //   label: Text("Add Effect"),
                                  //   icon: Icon(Icons.add),
                                  // ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),

        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            heroTag: "add_virtual_fab",
            shape: CircleBorder(),
            onPressed: _addVirtualForm,
            child: Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  // Global key to uniquely identify the Form and enable validation
  final _formKey = GlobalKey<FormState>();

  // The maximum desired width for the dialogue card on large screens
  static const double _cardMaxWidth = 500.0;
  final TextEditingController _name = TextEditingController(text: "");
  void _addVirtualForm() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // The Center widget ensures the dialogue is centered on the screen.
        return Center(
          // ConstrainedBox enforces the maximum width for the dialogue content.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _cardMaxWidth),
            child: Dialog(
              // The Dialog widget provides the raised, card-like appearance
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
              child: Padding(
                padding: const EdgeInsets.all(30.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    // Make sure the dialogue only takes the space its children need
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text(
                        'Add Virtual Strip',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      // Name Field
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                          hint: Text("New"),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 15),
                      // Submit Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text('Close'),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () async {
                              if (_formKey.currentState!.validate()) {
                                try {
                                  ledfxWorker.addNewVirtual(_name.text);
                                  Navigator.of(context).pop();
                                } catch (e) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(SnackBar(content: Text("Error - ${e.toString()}")));
                                }
                              }
                            },
                            child: const Text('Register'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
