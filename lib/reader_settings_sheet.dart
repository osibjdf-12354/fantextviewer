import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_store.dart';
import 'font_library.dart';
import 'models.dart';
import 'strings.dart';

class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.initialSettings,
    required this.initialFonts,
    required this.store,
    required this.onChanged,
    required this.onApplySettings,
    required this.onSave,
    required this.onMessage,
    required this.pickFont,
    this.fontLibrary,
  });

  final ReaderSettings initialSettings;
  final List<ImportedFont> initialFonts;
  final AppStore store;
  final ValueChanged<ReaderSettings> onChanged;
  final ValueChanged<ReaderSettings> onApplySettings;
  final Future<void> Function() onSave;
  final ValueChanged<String> onMessage;
  final Future<String?> Function() pickFont;
  final FontLibrary? fontLibrary;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late ReaderSettings _draft;
  late List<ImportedFont> _fonts;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialSettings;
    _fonts = [...widget.initialFonts];
  }

  void _change(ReaderSettings value) {
    setState(() => _draft = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final ratio = contrastRatio(_draft.background, _draft.foreground);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.displaySettings,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            const Text(AppStrings.readingMethod),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text(AppStrings.verticalScroll),
                  selected: _draft.mode == ReadingMode.scroll,
                  onSelected: (_) =>
                      _change(_draft.copyWith(mode: ReadingMode.scroll)),
                ),
                ChoiceChip(
                  label: const Text(AppStrings.swipe),
                  selected: _draft.mode == ReadingMode.page,
                  onSelected: (_) =>
                      _change(_draft.copyWith(mode: ReadingMode.page)),
                ),
                ChoiceChip(
                  key: const Key('reading-mode-tap'),
                  label: const Text(AppStrings.tap),
                  selected: _draft.mode == ReadingMode.tap,
                  onSelected: (_) =>
                      _change(_draft.copyWith(mode: ReadingMode.tap)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(AppStrings.pageTurnDirection),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('page-turn-horizontal'),
                  label: const Text(AppStrings.horizontalTurn),
                  selected:
                      _draft.pageTurnDirection == PageTurnDirection.horizontal,
                  onSelected: (_) => _change(
                    _draft.copyWith(
                      pageTurnDirection: PageTurnDirection.horizontal,
                    ),
                  ),
                ),
                ChoiceChip(
                  key: const Key('page-turn-vertical'),
                  label: const Text(AppStrings.verticalTurn),
                  selected:
                      _draft.pageTurnDirection == PageTurnDirection.vertical,
                  onSelected: (_) => _change(
                    _draft.copyWith(
                      pageTurnDirection: PageTurnDirection.vertical,
                    ),
                  ),
                ),
                ChoiceChip(
                  key: const Key('page-turn-both'),
                  label: const Text(AppStrings.bothDirections),
                  selected: _draft.pageTurnDirection == PageTurnDirection.both,
                  onSelected: (_) => _change(
                    _draft.copyWith(pageTurnDirection: PageTurnDirection.both),
                  ),
                ),
              ],
            ),
            if (_draft.pageTurnDirection == PageTurnDirection.both) ...[
              const SizedBox(height: 4),
              Text(
                AppStrings.bothDirectionsHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            SwitchListTile(
              key: const Key('page-turn-animation-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text(AppStrings.pageTurnAnimation),
              value: _draft.pageTurnAnimationEnabled,
              onChanged: (value) =>
                  _change(_draft.copyWith(pageTurnAnimationEnabled: value)),
            ),
            _SettingStepper(
              settingKey: 'auto-page-interval',
              label: AppStrings.autoPageInterval,
              value: _draft.autoPageIntervalSeconds.toDouble(),
              min: 1,
              max: 60,
              step: 1,
              fractionDigits: 0,
              onChanged: (value) => _change(
                _draft.copyWith(autoPageIntervalSeconds: value.round()),
              ),
            ),
            Text(
              AppStrings.autoModeHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            const Text(AppStrings.pageIndicator),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('page-display-current'),
                  label: const Text(AppStrings.currentPageOnly),
                  selected: !_draft.showTotalPages,
                  onSelected: (_) =>
                      _change(_draft.copyWith(showTotalPages: false)),
                ),
                ChoiceChip(
                  key: const Key('page-display-current-total'),
                  label: const Text(AppStrings.currentAndTotalPages),
                  selected: _draft.showTotalPages,
                  onSelected: (_) =>
                      _change(_draft.copyWith(showTotalPages: true)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(AppStrings.font),
            Align(
              alignment: Alignment.centerLeft,
              child: ChoiceChip(
                key: const Key('font-option-system'),
                label: const Text(AppStrings.systemFont),
                selected: _draft.fontFileName == null,
                onSelected: (_) => _change(_draft.copyWith(fontFileName: null)),
              ),
            ),
            for (final font in _fonts) _buildFontRow(font),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: widget.fontLibrary == null ? null : _importFont,
              icon: const Icon(Icons.add),
              label: const Text(AppStrings.importLocalFont),
            ),
            _SettingStepper(
              settingKey: 'font-size',
              label: AppStrings.fontSize,
              value: _draft.fontSize,
              min: 14,
              max: 36,
              step: 1,
              fractionDigits: 0,
              onChanged: (value) => _change(_draft.copyWith(fontSize: value)),
            ),
            _SettingStepper(
              settingKey: 'line-height',
              label: AppStrings.lineHeight,
              value: _draft.lineHeight,
              min: 1.2,
              max: 2.2,
              step: .1,
              fractionDigits: 1,
              onChanged: (value) => _change(_draft.copyWith(lineHeight: value)),
            ),
            _SettingStepper(
              settingKey: 'horizontal-padding',
              label: AppStrings.horizontalPadding,
              value: _draft.horizontalPadding,
              min: 8,
              max: 40,
              step: 1,
              fractionDigits: 0,
              onChanged: (value) =>
                  _change(_draft.copyWith(horizontalPadding: value)),
            ),
            const SizedBox(height: 8),
            const Text(AppStrings.paragraphIndent),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('paragraph-indent-none'),
                  label: const Text(AppStrings.none),
                  selected: _draft.paragraphIndent == 0,
                  onSelected: (_) =>
                      _change(_draft.copyWith(paragraphIndent: 0)),
                ),
                ChoiceChip(
                  key: const Key('paragraph-indent-one'),
                  label: const Text(AppStrings.oneCharacter),
                  selected: _draft.paragraphIndent == 1,
                  onSelected: (_) =>
                      _change(_draft.copyWith(paragraphIndent: 1)),
                ),
                ChoiceChip(
                  key: const Key('paragraph-indent-two'),
                  label: const Text(AppStrings.twoCharacters),
                  selected: _draft.paragraphIndent == 2,
                  onSelected: (_) =>
                      _change(_draft.copyWith(paragraphIndent: 2)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(AppStrings.colorTemplates),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _colorTemplates
                  .map(
                    (template) => IconButton(
                      key: Key('color-template-${template.name}'),
                      tooltip: template.name,
                      onPressed: () => _change(
                        _draft.copyWith(
                          background: template.background,
                          foreground: template.foreground,
                        ),
                      ),
                      icon: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Color(template.background.value),
                          border: Border.all(color: Colors.black26),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          AppStrings.previewCharacter,
                          style: TextStyle(
                            color: Color(template.foreground.value),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            _RgbEditor(
              background: _draft.background,
              foreground: _draft.foreground,
              onChanged: (background, foreground) => _change(
                _draft.copyWith(background: background, foreground: foreground),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Color(_draft.background.value),
              child: Text(
                AppStrings.fontPreview,
                key: const Key('font-preview'),
                style: TextStyle(
                  color: Color(_draft.foreground.value),
                  fontFamily: fontFamilyFor(_draft.fontFileName),
                  fontSize: 18,
                ),
              ),
            ),
            Text(AppStrings.contrastRatio(ratio.toStringAsFixed(2))),
            if (ratio < 4.5) ...[
              const Text(
                AppStrings.lowContrastWarning,
                style: TextStyle(color: Colors.red),
              ),
              TextButton(
                key: const Key('reset-accessible-colors'),
                onPressed: () => _change(
                  _draft.copyWith(
                    background: const RgbColor(196, 236, 187),
                    foreground: const RgbColor(32, 48, 32),
                  ),
                ),
                child: const Text(AppStrings.resetDefaultColors),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(AppStrings.keepScreenAwake),
              value: _draft.keepAwake,
              onChanged: (value) => _change(_draft.copyWith(keepAwake: value)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFontRow(ImportedFont font) {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ChoiceChip(
              key: Key('font-option-${font.fileName}'),
              label: Text(font.label),
              selected: _draft.fontFileName == font.fileName,
              onSelected: (_) async {
                try {
                  await widget.fontLibrary!.loadFont(font);
                  if (mounted) {
                    _change(_draft.copyWith(fontFileName: font.fileName));
                  }
                } catch (_) {
                  widget.onMessage(AppStrings.fontLoadFailed);
                }
              },
            ),
          ),
        ),
        IconButton(
          key: Key('delete-font-${font.fileName}'),
          tooltip: AppStrings.fontDeleteTooltip(font.label),
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _deleteFont(font),
        ),
      ],
    );
  }

  Future<void> _importFont() async {
    String? path;
    try {
      path = await widget.pickFont();
    } catch (_) {
      widget.onMessage(AppStrings.fontImportFailed);
      return;
    }
    if (path == null) return;
    try {
      final font = await widget.fontLibrary!.importFont(path);
      if (!mounted) return;
      setState(() {
        _fonts = [..._fonts, font]
          ..sort(
            (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
          );
      });
      _change(_draft.copyWith(fontFileName: font.fileName));
    } on FormatException catch (error) {
      widget.onMessage(error.message.toString());
    } catch (_) {
      widget.onMessage(AppStrings.fontImportFailed);
    }
  }

  Future<void> _deleteFont(ImportedFont font) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.fontDeleteTitle),
        content: Text(
          AppStrings.fontDeletePrompt(font.label) +
              (widget.fontLibrary!.isLoaded(font.fileName)
                  ? '\n\n${AppStrings.fontLoadedUntilRestart}'
                  : ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(AppStrings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final savedFontFileName = widget.store.data.settings.fontFileName;
    try {
      await widget.fontLibrary!.deleteFont(font);
    } catch (_) {
      widget.onMessage(AppStrings.fontDeleteFailed);
      return;
    }
    final latestSettings = widget.store.data.settings;
    final resetSaved =
        latestSettings.fontFileName == font.fileName ||
        (_draft.fontFileName == font.fileName &&
            latestSettings.fontFileName == savedFontFileName);
    if (resetSaved) {
      final resetSettings = latestSettings.copyWith(fontFileName: null);
      widget.onApplySettings(resetSettings);
      try {
        await widget.onSave();
      } catch (_) {
        widget.onMessage(AppStrings.fontDeletedSaveFailed);
      }
    }
    if (!mounted) return;
    setState(() {
      _fonts.removeWhere((item) => item.fileName == font.fileName);
    });
    if (_draft.fontFileName == font.fileName) {
      _change(_draft.copyWith(fontFileName: null));
    }
  }
}

class _SettingStepper extends StatelessWidget {
  const _SettingStepper({
    required this.settingKey,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.fractionDigits,
    required this.onChanged,
  });

  final String settingKey;
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final int fractionDigits;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          key: Key('$settingKey-decrease'),
          tooltip: AppStrings.settingDecrease(label),
          visualDensity: VisualDensity.compact,
          onPressed: value <= min ? null : () => onChanged(_next(-step)),
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 52,
          child: Text(
            value.toStringAsFixed(fractionDigits),
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          key: Key('$settingKey-increase'),
          tooltip: AppStrings.settingIncrease(label),
          visualDensity: VisualDensity.compact,
          onPressed: value >= max ? null : () => onChanged(_next(step)),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  double _next(double delta) => double.parse(
    (value + delta).clamp(min, max).toStringAsFixed(fractionDigits),
  );
}

class _RgbEditor extends StatefulWidget {
  const _RgbEditor({
    required this.background,
    required this.foreground,
    required this.onChanged,
  });

  final RgbColor background;
  final RgbColor foreground;
  final void Function(RgbColor background, RgbColor foreground) onChanged;

  @override
  State<_RgbEditor> createState() => _RgbEditorState();
}

class _RgbEditorState extends State<_RgbEditor> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(6, (_) => TextEditingController());
    _setValues();
  }

  @override
  void didUpdateWidget(_RgbEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.background != widget.background ||
        oldWidget.foreground != widget.foreground) {
      _setValues();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setValues() {
    final values = [
      widget.background.red,
      widget.background.green,
      widget.background.blue,
      widget.foreground.red,
      widget.foreground.green,
      widget.foreground.blue,
    ];
    for (var index = 0; index < values.length; index++) {
      final text = '${values[index]}';
      if (_controllers[index].text == text) continue;
      _controllers[index].value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void _emit() {
    final values = _controllers
        .map((controller) => int.tryParse(controller.text))
        .toList();
    if (values.any((value) => value == null)) return;
    final background = RgbColor.tryCreate(values[0]!, values[1]!, values[2]!);
    final foreground = RgbColor.tryCreate(values[3]!, values[4]!, values[5]!);
    if (background != null && foreground != null) {
      widget.onChanged(background, foreground);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(AppStrings.backgroundRgb),
        _row(0, 'background'),
        const SizedBox(height: 8),
        const Text(AppStrings.foregroundRgb),
        _row(3, 'foreground'),
      ],
    );
  }

  Widget _row(int start, String prefix) {
    return Row(
      children: List.generate(3, (index) {
        final channel = const ['red', 'green', 'blue'][index];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == 2 ? 0 : 8),
            child: TextField(
              key: Key('$prefix-$channel'),
              controller: _controllers[start + index],
              keyboardType: TextInputType.number,
              onChanged: (_) {
                setState(() {});
                _emit();
              },
              decoration: InputDecoration(
                labelText: const ['R', 'G', 'B'][index],
                errorText: _channelError(_controllers[start + index].text),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        );
      }),
    );
  }

  String? _channelError(String text) {
    final value = int.tryParse(text);
    return value == null || value < 0 || value > 255 ? '0~255' : null;
  }
}

class _ColorTemplate {
  const _ColorTemplate(this.name, this.background, this.foreground);

  final String name;
  final RgbColor background;
  final RgbColor foreground;
}

const _colorTemplates = [
  _ColorTemplate(
    AppStrings.defaultGreen,
    RgbColor(196, 236, 187),
    RgbColor(32, 48, 32),
  ),
  _ColorTemplate(
    AppStrings.paper,
    RgbColor(255, 253, 248),
    RgbColor(32, 32, 32),
  ),
  _ColorTemplate(
    AppStrings.night,
    RgbColor(18, 18, 18),
    RgbColor(232, 232, 232),
  ),
  _ColorTemplate(
    AppStrings.sepia,
    RgbColor(244, 236, 216),
    RgbColor(59, 49, 38),
  ),
];

double contrastRatio(RgbColor first, RgbColor second) {
  final firstLuminance = Color(first.value).computeLuminance();
  final secondLuminance = Color(second.value).computeLuminance();
  final light = math.max(firstLuminance, secondLuminance);
  final dark = math.min(firstLuminance, secondLuminance);
  return (light + .05) / (dark + .05);
}
