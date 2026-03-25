import 'package:flutter/material.dart';
import 'package:ledfx/ui/pages/adaptive_layout.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.layout});
  final AdaptiveLayout layout;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Center(child: Text("Settings"));
  }
}
