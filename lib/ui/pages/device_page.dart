import 'package:flutter/material.dart';
import 'package:ledfx/src/devices/device.dart';
import 'package:ledfx/ui/pages/adaptive_layout.dart';
import 'package:ledfx/ui/visualizer/visualizer_painter.dart';
import 'package:ledfx/worker.dart';

class DevicePage extends StatefulWidget {
  const DevicePage({super.key, required this.layout});
  final AdaptiveLayout layout;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
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
            valueListenable: ledfxWorker.devices,
            builder: (context, devices, child) {
              return ListView.separated(
                shrinkWrap: true,
                separatorBuilder: (context, index) => SizedBox(height: 8),
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final d = devices[index];
                  final deviceID = d["id"];
                  final deviceConfig = DeviceConfig.fromJson((d["config"] as Map<String, dynamic>));

                  return ExpansionTile(
                    key: ValueKey(deviceID),
                    maintainState: true,
                    initiallyExpanded: _expandedStates[deviceID] ?? false,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _expandedStates[deviceID] = expanded;
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
                    title: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            RichText(
                              text: TextSpan(
                                text: deviceConfig.name,
                                children: [
                                  TextSpan(
                                    text: "     ID: $deviceID",
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
                                            ledfxWorker.removeDevice(deviceID);
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
                        // Visualizer Strip
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            height: 10,
                            child: ValueListenableBuilder<List<int>>(
                              valueListenable: ledfxWorker.getDeviceRgbNotifier(deviceID),
                              builder: (BuildContext context, List<int> data, Widget? child) {
                                if (data.isEmpty) return const SizedBox.shrink();
                                return CustomPaint(
                                  painter: VisualizerPainter(rgb: data, ledCount: 300),
                                  size: const Size(double.infinity, 50),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Type: ${deviceConfig.type}"),
                            Text("Address: ${deviceConfig.address}"),
                            Text("Pixel Count: ${deviceConfig.pixelCount}"),
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
              heroTag: "add_device_fab",
              shape: CircleBorder(),
              onPressed: _addDeviceForm,
              child: Icon(Icons.add)),
        ),
      ],
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
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                      // Name Field
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
                                  ledfxWorker.addDevice(_name.text, _type.text, _address.text);
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
