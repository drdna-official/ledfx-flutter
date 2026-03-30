import 'package:flutter/material.dart';
import 'package:ledfx/src/devices/device.dart';
import 'package:ledfx/src/virtual.dart';
import 'package:ledfx/worker.dart';

class SegmentsPage extends StatefulWidget {
  const SegmentsPage({super.key, required this.virtualID, required this.virtualName});
  final String virtualID;
  final String virtualName;

  @override
  State<SegmentsPage> createState() => _SegmentsPageState();
}

class _SegmentsPageState extends State<SegmentsPage> {
  final LEDFxWorker ledfxWorker = LEDFxWorker.instance;

  // The maximum desired width for the dialogue card on large screens
  static const double _cardMaxWidth = 500.0;

  @override
  Widget build(BuildContext context) {
    // Current devices available in the worker
    final Map<String, DeviceConfig> devices = ledfxWorker.devices.value.isEmpty
        ? {}
        : ledfxWorker.devices.value
              .map((e) => {e["id"] as String: DeviceConfig.fromJson(e["config"] as Map<String, dynamic>)})
              .reduce((a, b) => {...a, ...b});

    return Scaffold(
      appBar: AppBar(title: Text('Segments - ${widget.virtualName}'), backgroundColor: Colors.transparent),
      body: ValueListenableBuilder(
        valueListenable: ledfxWorker.virtuals,
        builder: (context, virtuals, _) {
          final virtualData = virtuals.firstWhere((e) => e["id"] == widget.virtualID, orElse: () => {});
          final List<SegmentConfig> segments = virtualData.isEmpty
              ? []
              : (virtualData["segments"] as List<dynamic>)
                    .map((e) => SegmentConfig.fromJson(e as Map<String, dynamic>))
                    .toList();

          final configData = virtualData["config"] as Map<String, dynamic>;
          final virtualConfig = VirtualConfig.fromJson(configData);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Change Mode"),
                    SegmentedButton(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: "span", label: Text("Span")),
                        ButtonSegment(value: "copy", label: Text("Copy")),
                      ],
                      selected: {virtualConfig.segmentMapping},
                      onSelectionChanged: (v) {
                        virtualConfig.segmentMapping = v.first;
                        ledfxWorker.updateVirtualConfig(widget.virtualID, virtualConfig);
                      },
                    ),
                  ],
                ),
              ),
              ListView.separated(
                shrinkWrap: true,
                itemCount: segments.length,
                padding: const EdgeInsets.all(8),
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final segment = segments[index];
                  return Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                devices[segment.deviceID]?.name ?? "Unknown Device",
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _editSegmentForm(devices, segment, index),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () => _deleteSegment(segment, index),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Text("Start: ${segment.start}"),
                        Text("End: ${segment.end}"),
                        Text("Reversed: ${segment.inverted ? 'yes' : 'no'}"),
                      ],
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: "add_segment_fab",
        shape: const CircleBorder(),
        onPressed: () => _addSegmentForm(devices),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _addSegmentForm(Map<String, DeviceConfig> devices) {
    _showSegmentForm(devices);
  }

  void _editSegmentForm(Map<String, DeviceConfig> devices, SegmentConfig segment, int index) {
    _showSegmentForm(devices, initialSegment: segment, editIndex: index);
  }

  void _deleteSegment(SegmentConfig segment, int index) {
    final currentVirtual = ledfxWorker.virtuals.value.firstWhere((e) => e["id"] == widget.virtualID);
    final List<SegmentConfig> currentSegments = (currentVirtual["segments"] as List<dynamic>)
        .map((e) => SegmentConfig.fromJson(e as Map<String, dynamic>))
        .toList();

    currentSegments.removeAt(index);
    ledfxWorker.updateVirtualSegments(widget.virtualID, currentSegments);
  }

  void _showSegmentForm(Map<String, DeviceConfig> devices, {SegmentConfig? initialSegment, int? editIndex}) {
    // Global key for the form in the dialog
    final formKey = GlobalKey<FormState>();
    String? selectedDeviceID = initialSegment?.deviceID;

    RangeValues currentRange = initialSegment != null
        ? RangeValues(initialSegment.start.toDouble(), initialSegment.end.toDouble())
        : const RangeValues(0, 0);

    bool inverted = initialSegment?.inverted ?? false;
    final startController = TextEditingController(text: currentRange.start.round().toString());
    final endController = TextEditingController(text: currentRange.end.round().toString());
    bool isManualInputEnabled = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final device = selectedDeviceID != null ? devices[selectedDeviceID] : null;
            final double maxPixel = (device?.pixelCount.toDouble() ?? 101) - 1;

            final currentVirtual = ledfxWorker.virtuals.value.firstWhere((e) => e["id"] == widget.virtualID);
            final List<SegmentConfig> currentSegments = (currentVirtual["segments"] as List<dynamic>)
                .map((e) => SegmentConfig.fromJson(e as Map<String, dynamic>))
                .toList();

            final bool overlaps =
                selectedDeviceID != null &&
                currentSegments
                    .asMap()
                    .entries
                    .where((entry) => entry.key != editIndex && entry.value.deviceID == selectedDeviceID)
                    .any(
                      (entry) =>
                          (entry.value.start <= currentRange.end.round() &&
                          entry.value.end >= currentRange.start.round()),
                    );

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _cardMaxWidth),
                child: Dialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                  child: Padding(
                    padding: const EdgeInsets.all(30.0),
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            initialSegment == null ? 'Add New Segment' : 'Edit Segment',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          RepaintBoundary(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedDeviceID,
                              decoration: InputDecoration(
                                labelText: 'Device',
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              ),
                              items: devices.keys.map((String deviceID) {
                                return DropdownMenuItem<String>(value: deviceID, child: Text(devices[deviceID]!.name));
                              }).toList(),
                              onChanged: (String? newValue) {
                                setDialogState(() {
                                  selectedDeviceID = newValue;
                                  if (newValue != null) {
                                    double maxVal = (devices[newValue]!.pixelCount.toDouble() - 1);
                                    currentRange = RangeValues(0, maxVal);
                                    startController.text = "0";
                                    endController.text = maxVal.toInt().toString();
                                  }
                                });
                              },
                              validator: (value) => value == null ? 'Please select a device' : null,
                            ),
                          ),
                          if (selectedDeviceID != null) ...[
                            const SizedBox(height: 20),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: startController,
                                    enabled: isManualInputEnabled,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: "Start", isDense: true),
                                    onChanged: (val) {
                                      int? start = int.tryParse(val);
                                      if (start != null) {
                                        setDialogState(() {
                                          double clampedStart = start.clamp(0, maxPixel).toDouble();
                                          double currentEnd = currentRange.end;
                                          if (clampedStart > currentEnd) clampedStart = currentEnd;
                                          currentRange = RangeValues(clampedStart, currentEnd);
                                        });
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: endController,
                                    enabled: isManualInputEnabled,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: "End", isDense: true),
                                    onChanged: (val) {
                                      int? end = int.tryParse(val);
                                      if (end != null) {
                                        setDialogState(() {
                                          double clampedEnd = end.clamp(0.0, maxPixel).toDouble();
                                          double currentStart = currentRange.start;
                                          if (clampedEnd < currentStart) clampedEnd = currentStart;
                                          currentRange = RangeValues(currentStart, clampedEnd);
                                        });
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(isManualInputEnabled ? Icons.check : Icons.edit),
                                  onPressed: () => setDialogState(() => isManualInputEnabled = !isManualInputEnabled),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            RangeSlider(
                              values: currentRange,
                              min: 0,
                              max: maxPixel > 0 ? maxPixel : 1,
                              divisions: maxPixel > 0 ? maxPixel.toInt() : 1,
                              labels: RangeLabels(
                                currentRange.start.round().toString(),
                                currentRange.end.round().toString(),
                              ),
                              onChanged: (RangeValues values) {
                                setDialogState(() {
                                  currentRange = values;
                                  startController.text = values.start.round().toString();
                                  endController.text = values.end.round().toString();
                                });
                              },
                            ),
                            if (overlaps)
                              const Padding(
                                padding: EdgeInsets.only(top: 8.0),
                                child: Text(
                                  "Warning: This range overlaps with an existing segment on this device.",
                                  style: TextStyle(color: Colors.red, fontSize: 12),
                                ),
                              ),
                            const SizedBox(height: 10),
                            CheckboxListTile(
                              title: const Text("Inverted"),
                              value: inverted,
                              onChanged: (bool? value) {
                                setDialogState(() {
                                  inverted = value ?? false;
                                });
                              },
                            ),
                          ],
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: selectedDeviceID == null || overlaps
                                    ? null
                                    : () async {
                                        if (formKey.currentState!.validate()) {
                                          try {
                                            final newSegment = SegmentConfig(
                                              selectedDeviceID!,
                                              currentRange.start.round(),
                                              currentRange.end.round(),
                                              inverted,
                                            );

                                            if (editIndex != null) {
                                              currentSegments[editIndex] = newSegment;
                                            } else {
                                              currentSegments.add(newSegment);
                                            }

                                            ledfxWorker.updateVirtualSegments(widget.virtualID, currentSegments);
                                            Navigator.of(context).pop();
                                          } catch (e) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(SnackBar(content: Text("Error - ${e.toString()}")));
                                          }
                                        }
                                      },
                                child: Text(initialSegment == null ? 'Add Segment' : 'Update Segment'),
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
      },
    );
  }
}
