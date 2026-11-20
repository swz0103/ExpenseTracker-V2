import 'package:flutter/material.dart';

import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';

// Picking a merchant or tags: typed, or chosen from those used before.

/// A merchant's name, typed or picked from those used before.
class MerchantPicker extends StatefulWidget {
  const MerchantPicker({
    super.key,
    required this.known,
    required this.initial,
    required this.onDone,
  });

  final List<String> known;
  final String initial;
  final ValueChanged<String> onDone;

  @override
  State<MerchantPicker> createState() => _MerchantPickerState();
}

class _MerchantPickerState extends State<MerchantPicker> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typed = _text.text.trim();
    final matches = [
      for (final name in widget.known)
        if (typed.isEmpty || name.toLowerCase().contains(typed.toLowerCase()))
          name,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _text,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (value) => widget.onDone(value.trim()),
          decoration: InputDecoration(
            hintText: '商家名稱',
            filled: true,
            fillColor: AppColors.tile,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.large),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: Space.s2),
        Column(
          children: [
            if (typed.isNotEmpty && !widget.known.contains(typed))
              ListTile(
                leading: const GlyphIcon(Glyph.add, color: AppColors.accent),
                title: Text('新增「$typed」'),
                onTap: () => widget.onDone(typed),
              ),
            for (final name in matches.take(12))
              ListTile(
                leading: const GlyphIcon(Glyph.store, color: AppColors.accent),
                title: Text(name),
                onTap: () => widget.onDone(name),
              ),
            if (widget.initial.isNotEmpty)
              ListTile(
                leading: const GlyphIcon(Glyph.close, color: AppColors.muted),
                title: const Text('不記商家'),
                onTap: () => widget.onDone(''),
              ),
          ],
        ),
      ],
    );
  }
}

/// Tags to put on an entry: those in use, and new ones.
class TagPicker extends StatefulWidget {
  const TagPicker({
    super.key,
    required this.known,
    required this.initial,
    required this.onDone,
  });

  final List<String> known;
  final List<String> initial;
  final ValueChanged<List<String>> onDone;

  @override
  State<TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<TagPicker> {
  late final _picked = [...widget.initial];
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    final tag = _text.text.trim().replaceAll('#', '');
    if (tag.isEmpty) return;
    setState(() {
      if (!_picked.contains(tag) && _picked.length < 16) _picked.add(tag);
      _text.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = {...widget.known, ..._picked}.toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in all)
              FilterChip(
                label: Text('#$tag'),
                selected: _picked.contains(tag),
                onSelected: (on) => setState(() {
                  if (on) {
                    if (_picked.length < 16) _picked.add(tag);
                  } else {
                    _picked.remove(tag);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: Space.s3),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  hintText: '新標籤',
                  filled: true,
                  fillColor: AppColors.tile,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.large),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '加入',
              onPressed: _add,
              icon: const GlyphIcon(Glyph.add, color: AppColors.accent),
            ),
          ],
        ),
        const SizedBox(height: Space.s3),
        FilledButton(
          onPressed: () => widget.onDone(_picked),
          style: solidButton(
            AppColors.accent,
            minimumSize: Size.fromHeight(44),
          ),
          child: const Text(Words.done),
        ),
      ],
    );
  }
}
