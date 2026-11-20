import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';

class ExIcon extends StatelessWidget {
  final String src; // 'asset:assets/icons/x.svg' or a file path
  final double size;
  const ExIcon(this.src, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final inner = src.startsWith('asset:')
        ? SvgPicture.asset(src.substring(6), width: size * .8, height: size * .8)
        : SvgPicture.file(File(src), width: size * .8, height: size * .8);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(size * .23)),
      alignment: Alignment.center,
      child: inner,
    );
  }
}

/// A row of pills. Single choice when [multi] is false.
class Pills<T> extends StatelessWidget {
  final List<T> values;
  final String Function(T) label;
  final Set<T> selected;
  final void Function(T) onTap;
  const Pills({super.key, required this.values, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final v in values)
            ChoiceChip(
              label: Text(label(v), style: TextStyle(color: selected.contains(v) ? C.onTeal : C.text, fontWeight: selected.contains(v) ? FontWeight.w600 : FontWeight.normal)),
              selected: selected.contains(v),
              showCheckmark: false,
              onSelected: (_) => onTap(v),
            ),
        ],
      );
}

class Q extends StatelessWidget {
  final String text;
  const Q(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      );
}

class Tag extends StatelessWidget {
  final String text;
  final bool ai;
  const Tag(this.text, {super.key, this.ai = false});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: ai ? const Color(0xFF3B2F0B) : C.navy, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 11, color: ai ? C.gold : const Color(0xFFCFE3FF))),
      );
}

class Dim extends StatelessWidget {
  final String text;
  final double size;
  const Dim(this.text, {super.key, this.size = 13});
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(color: C.dim, fontSize: size));
}

/// Big − value + control for sweaty thumbs.
class BigStepper extends StatelessWidget {
  final String value;
  final String unit;
  final VoidCallback onMinus, onPlus;
  final VoidCallback? onTapValue;
  const BigStepper({super.key, required this.value, required this.unit, required this.onMinus, required this.onPlus, this.onTapValue});

  @override
  Widget build(BuildContext context) {
    Widget b(IconData i, VoidCallback f) => SizedBox(
          width: 52,
          height: 52,
          child: IconButton.filled(onPressed: f, icon: Icon(i, size: 26), style: IconButton.styleFrom(backgroundColor: C.line, foregroundColor: C.text, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
        );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        b(Icons.remove, onMinus),
        Expanded(
          child: InkWell(
            onTap: onTapValue,
            child: Column(children: [
              FittedBox(child: Text(value, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]))),
              Dim(unit, size: 12),
            ]),
          ),
        ),
        b(Icons.add, onPlus),
      ]),
    );
  }
}

/// A plain-words problem message: gold with an icon (never red).
class Problem extends StatelessWidget {
  final List<String> lines;
  const Problem(this.lines, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF3B2F0B), borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: C.gold),
          const SizedBox(width: 10),
          Expanded(child: Text(lines.take(6).join('\n'), style: const TextStyle(color: C.gold))),
        ]),
      );
}

void toast(BuildContext context, String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

/// A yes/no sheet (dialogs are built into the app, nothing system-level).
Future<bool> confirm(BuildContext context, String title, String body, {String yes = 'Yes', String no = 'Cancel'}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: C.card,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Dim(body, size: 14),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(c, false), child: Text(no))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes))),
          ]),
        ]),
      ),
    ),
  );
  return r ?? false;
}
