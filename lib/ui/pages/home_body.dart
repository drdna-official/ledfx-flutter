import 'package:flutter/material.dart';
import 'package:ledfx/ui/pages/adaptive_layout.dart';
import 'package:ledfx/worker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

Future<bool> requestNotificationPermission() async {
  if (await Permission.notification.isGranted) return true;
  final status = await Permission.notification.request();
  return status.isGranted;
}

class HomeBody extends StatefulWidget {
  const HomeBody({super.key, required this.layout});
  final AdaptiveLayout layout;

  @override
  State<HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<HomeBody> {
  final LEDFxWorker ledfxWorker = LEDFxWorker.instance;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        spacing: 8,
        children: [
          ValueListenableBuilder(
            valueListenable: ledfxWorker.audioDevices,
            builder: (context, devices, child) {
              return Row(
                children: [
                  Text("Current Selected Device: "),
                  if (devices.isNotEmpty)
                    Text(
                      devices[ledfxWorker.activeAudioDeviceIndex.value].name,
                      style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
