import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/worker.dart';

class EffectPage extends StatefulWidget {
  const EffectPage({super.key, required this.virtualID, required this.virtualName});
  final String virtualID;
  final String virtualName;

  @override
  State<EffectPage> createState() => _EffectPageState();
}

class _EffectPageState extends State<EffectPage> {
  final LEDFxWorker ledfxWorker = LEDFxWorker.instance;

  updateEffectConfig(EffectConfig? effect) {
    if (effect != null) {
      ledfxWorker.setVirtualEffect(widget.virtualID, effect);
    }
  }

  Widget _buildColorTile(String title, Color color, void Function(Color) onColorChanged, EffectConfig activeEffect) {
    return ListTile(
      title: Text(title),
      trailing: ColorIndicator(
        color: color,
        onSelectFocus: false,
        onSelect: () async {
          final Color colorBeforeDialog = color;
          final Color newColor = await showColorPickerDialog(
            context,
            colorBeforeDialog,
            pickersEnabled: {
              ColorPickerType.primary: true,
              ColorPickerType.wheel: true,
              ColorPickerType.accent: false,
              ColorPickerType.custom: false,
              ColorPickerType.both: false,
              ColorPickerType.bw: false,
              ColorPickerType.customSecondary: false,
            },

            enableShadesSelection: false,
            enableOpacity: false,
            showMaterialName: false,
            title: null,
            heading: null,
            subheading: null,
            tonalSubheading: null,
            wheelSubheading: null,
            opacitySubheading: null,
            recentColorsSubheading: null,

            showColorCode: true,
            colorCodeHasColor: true,

            elevation: 2.0,
            hasBorder: true,

            copyPasteBehavior: ColorPickerCopyPasteBehavior(
              copyButton: false,
              pasteButton: false,
              ctrlC: false,
              ctrlV: false,
              autoFocus: false,
              longPressMenu: false,
              editFieldCopyButton: false,
              editUsesParsedPaste: false,
              secondaryMenu: false,
            ),

            constraints: const BoxConstraints(minWidth: 400, maxWidth: 400, minHeight: 350),
          );
          onColorChanged(newColor);
          updateEffectConfig(activeEffect);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    EffectConfig? activeEffect;

    return Scaffold(
      appBar: AppBar(title: Text('Effect - ${widget.virtualName}'), backgroundColor: Colors.transparent),
      body: ValueListenableBuilder(
        valueListenable: ledfxWorker.virtuals,
        builder: (context, virtuals, _) {
          final virtual = virtuals.firstWhere((e) => e["id"] == widget.virtualID, orElse: () => {});
          final effectData = virtual.isEmpty ? null : virtual["activeEffect"];
          if (effectData != null) {
            activeEffect = EffectConfig.fromJson(effectData as Map<String, dynamic>);
          }

          return StatefulBuilder(
            builder: (context, setLocalState) {
              return Column(
                children: [
                  Text(widget.virtualName),
                  DropdownButton<EffectType>(
                    value: activeEffect?.type,
                    items: EffectType.values.where((v) => v != EffectType.unknown).map((effect) {
                      return DropdownMenuItem<EffectType>(value: effect, child: Text(effect.fullName));
                    }).toList(),
                    onChanged: (effect) {
                      if (effect != null) {
                        activeEffect = EffectConfig(name: effect.fullName, type: effect, mirror: true, blur: 3.0);
                        updateEffectConfig(activeEffect);
                      }
                    },
                  ),
                  if (activeEffect != null) ...[
                    SwitchListTile(
                      title: Text("Mirror"),
                      value: activeEffect!.mirror,
                      onChanged: (value) {
                        activeEffect!.mirror = value;
                        setLocalState(() {});
                        updateEffectConfig(activeEffect);
                      },
                    ),
                    SwitchListTile(
                      title: Text("Flip"),
                      value: activeEffect!.flip,
                      onChanged: (value) {
                        activeEffect!.flip = value;
                        setLocalState(() {});
                        updateEffectConfig(activeEffect);
                      },
                    ),

                    Slider(
                      value: activeEffect!.brightness,
                      onChanged: (value) {
                        activeEffect!.brightness = value;
                        setLocalState(() {});
                      },
                      onChangeEnd: (value) {
                        updateEffectConfig(activeEffect);
                      },
                    ),

                    if (activeEffect!.type == EffectType.energy) ...[
                      ListView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildColorTile(
                            "Lows Color",
                            activeEffect!.lowsColor ?? Colors.red.shade700,
                            (c) => activeEffect!.lowsColor = c,
                            activeEffect!,
                          ),
                          _buildColorTile(
                            "Mids Color",
                            activeEffect!.midsColor ?? Colors.amber.shade700,
                            (c) => activeEffect!.midsColor = c,
                            activeEffect!,
                          ),
                          _buildColorTile(
                            "Highs Color",
                            activeEffect!.highColor ?? Colors.blue.shade800,
                            (c) => activeEffect!.highColor = c,
                            activeEffect!,
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}
