import 'package:flutter/material.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/worker.dart';
import 'package:ledfx/ui/visualizer/visualizer_painter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

Future<bool> requestNotificationPermission() async {
  if (await Permission.notification.isGranted) return true;
  final status = await Permission.notification.request();
  return status.isGranted;
}

class HomeBody extends StatefulWidget {
  const HomeBody({super.key});

  @override
  State<HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<HomeBody> {
  final LEDFxWorker ledfxWorker = LEDFxWorker.instance;
  final Map<String, bool> _expandedStates = {};
  late StreamSubscription<String> _infoSubscription;

  @override
  void dispose() {
    _infoSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _infoSubscription = ledfxWorker.infoStream.listen((info) {
      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(info)));
      }
    });

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(onPressed: _addDeviceForm, label: Text("Add Device"), icon: Icon(Icons.add)),
              ElevatedButton.icon(
                onPressed: () {
                  ledfxWorker.requestState();
                },
                label: Text("Refresh"),
              ),
            ],
          ),
          ValueListenableBuilder(
            valueListenable: ledfxWorker.audioDevices,
            builder: (context, devices, child) {
              return Row(
                children: [
                  Text("Current Selected Device"),
                  if (devices.isNotEmpty) Text(devices[ledfxWorker.activeAudioDeviceIndex.value].name),
                ],
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  ledfxWorker.startAudioCapture();
                },
                label: Text("Start Audio Capture"),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  ledfxWorker.stopAudioCapture();
                },
                label: Text("Stop Audio Capture"),
              ),
            ],
          ),
          ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: ledfxWorker.virtuals,
            builder: (context, virtuals, child) {
              return ListView.separated(
                shrinkWrap: true,
                separatorBuilder: (context, index) => SizedBox(height: 8),
                itemCount: virtuals.length,
                itemBuilder: (context, index) {
                  final v = virtuals[index];
                  final configMap = v["config"] as Map<String, dynamic>;
                  return ExpansionTile(
                    key: ValueKey(v["id"]),
                    maintainState: true,
                    dense: true,
                    childrenPadding: EdgeInsets.zero,
                    collapsedShape: RoundedRectangleBorder(
                      side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Colors.grey.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        RichText(
                          text: TextSpan(
                            text: "${configMap["name"] ?? "Virtual Device"}",
                            children: [
                              TextSpan(
                                text: "     ID: ${configMap["deviceID"]}",
                                style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text("Remove Device"),
                                  content: Text("Are you sure you want to remove this device?"),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                      },
                                      child: Text("Cancel"),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        ledfxWorker.removeDevice(configMap["deviceID"]);
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
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _expandedStates[v["id"]] = expanded;
                      });
                    },
                    children: [
                      // VISUALIZER STRIP
                      if (_expandedStates[v["id"]] ?? false)
                        SizedBox(
                          height: 10,
                          child: ValueListenableBuilder<List<int>>(
                            valueListenable: ledfxWorker.getDeviceRgbNotifier(v["deviceID"]),
                            builder: (BuildContext context, List<int> data, Widget? child) {
                              if (data.isEmpty) return const SizedBox.shrink();
                              return CustomPaint(
                                painter: VisualizerPainter(rgb: data, ledCount: 300),
                                size: const Size(double.infinity, 50),
                              );
                            },
                          ),
                        ),
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
                                    Text("virtual ID: ${v["id"]}"),
                                    Text(
                                      "Active Effect: ${v["activeEffect"] != null ? v["activeEffect"]["name"] : 'None'}",
                                    ),
                                    Switch(
                                      value: v["active"] ?? false,
                                      onChanged: (bool newVal) {
                                        ledfxWorker.toggleVirtual(v["id"], newVal);
                                      },
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
                                      ledfxWorker.setEffect(
                                        v["id"],
                                        EffectConfig(name: "wavelength", mirror: true, blur: 3.0),
                                      );
                                    },
                                    label: Text("Add Effect"),
                                    icon: Icon(Icons.add),
                                  ),
                                  SizedBox(height: 4),
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
        ],
      ),
    );
  }

  // Global key to uniquely identify the Form and enable validation
  final _formKey = GlobalKey<FormState>();

  // The maximum desired width for the dialogue card on large screens
  static const double _cardMaxWidth = 500.0;
  final TextEditingController _name = TextEditingController(text: "");
  final TextEditingController _address = TextEditingController(text: "192.168.0.170");
  final TextEditingController _type = TextEditingController(text: "wled");
  void _addDeviceForm() {
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
                        'Add New Device',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),

                      // Device Type
                      DropdownButtonFormField<String>(
                        initialValue: _type.text,
                        decoration: const InputDecoration(labelText: 'DeviceType', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: "wled", child: Text("WLED")),
                          DropdownMenuItem(value: "dummy", child: Text("Dummy")),
                        ],
                        onChanged: (value) {
                          _type.text = value!;
                        },
                      ),
                      const SizedBox(height: 15),
                      // Address Field
                      TextFormField(
                        controller: _address,
                        decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder()),
                        validator: (value) {
                          if (_type.text != "dummy" && (value == null || value.isEmpty)) {
                            return 'Please enter a address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 15),
                      // Address Field
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                          hint: Text("My Device"),
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
                      ElevatedButton(
                        onPressed: () async {
                          if (_formKey.currentState!.validate()) {
                            try {
                              ledfxWorker.addDevice(_name.text, _type.text, _address.text);
                              Navigator.of(context).pop();
                            } catch (e) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text("Error - ${e.toString()}")));
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                        child: const Text('Register'),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                        child: const Text('Close'),
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
