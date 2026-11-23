import 'dart:async';
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
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: ai ? C.gold : const Color(0xFFCFE3FF))),
      );
}

class Dim extends StatelessWidget {
  final String text;
  final double size;
  const Dim(this.text, {super.key, this.size = 13});
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(color: C.dim, fontSize: size < minText ? minText : size));
}

/// No text in the app is smaller than this (F365).
const minText = 12.0;

/// Painted chart labels follow the phone's text size up to this much: they sit in a chart of
/// fixed height, whose margins are made for it (F364).
const chartScaleMax = 1.35;

/// The style for labels painted on charts: 12 at the phone's text size (up to [chartScaleMax]).
TextStyle paintLabel(BuildContext c, {Color color = C.dim}) =>
    (Theme.of(c).textTheme.bodySmall ?? const TextStyle()).copyWith(color: color, fontSize: minText * (MediaQuery.textScalerOf(c).scale(minText) / minText).clamp(1.0, chartScaleMax));

/// How tall one line of [s] is when painted.
double textHeight(TextStyle s) => (TextPainter(text: TextSpan(text: 'Mg', style: s), textDirection: TextDirection.ltr)..layout()).height;

/// F085 left-handed mode: rows of thumb controls are laid out right to left (text is unchanged).
bool leftHandedLayout = false;
TextDirection? get thumbRow => leftHandedLayout ? TextDirection.rtl : null;

/// Big − value + control for sweaty thumbs. Hold − or + to keep counting.
class BigStepper extends StatefulWidget {
  final String value;
  final String unit;
  final VoidCallback onMinus, onPlus;
  final VoidCallback? onTapValue;
  const BigStepper({super.key, required this.value, required this.unit, required this.onMinus, required this.onPlus, this.onTapValue});

  @override
  State<BigStepper> createState() => _BigStepperState();
}

class _BigStepperState extends State<BigStepper> {
  Timer? _repeat;

  void _hold(VoidCallback f) {
    _repeat?.cancel();
    var n = 0;
    _repeat = Timer.periodic(const Duration(milliseconds: 90), (_) {
      n++;
      if (n % (n > 15 ? 1 : 2) == 0) f(); // slower at first, then faster
    });
  }

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final value = w.value, unit = w.unit, onTapValue = w.onTapValue;
    // narrow (two steppers side by side): 48 dp buttons, so the number between keeps a 48 dp tap area too (F367)
    Widget b(IconData i, VoidCallback f, double side, String say) => GestureDetector(
          excludeFromSemantics: true, // hold-to-repeat is a shortcut; TalkBack taps the button (F368)
          onLongPressStart: (_) => _hold(f),
          onLongPressEnd: (_) => _stop(),
          onLongPressCancel: _stop,
          child: SizedBox(
            width: side,
            height: 56,
            // a label, not a tooltip: a tooltip would take the hold-to-repeat
            child: IconButton.filled(onPressed: f, icon: Icon(i, size: 28, semanticLabel: say), style: IconButton.styleFrom(backgroundColor: C.line, foregroundColor: C.text, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
          ),
        );
    final onMinus = w.onMinus, onPlus = w.onPlus;
    return LayoutBuilder(builder: (c, outer) {
      final narrow = outer.maxWidth < 2 * 56 + 64 + 16;
      return Container(
      padding: EdgeInsets.all(narrow ? 4 : 8),
      decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(14)),
      child: LayoutBuilder(builder: (c, box) {
        final side = narrow ? 48.0 : 56.0;
        return Row(textDirection: thumbRow, children: [
          b(Icons.remove, onMinus, side, 'Less, $unit'),
          Expanded(
            child: InkWell(
              onTap: onTapValue,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  FittedBox(child: Text(value, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]))),
                  Dim(unit, size: 12),
                ]),
              ),
            ),
          ),
          b(Icons.add, onPlus, side, 'More, $unit'),
        ]);
      }),
      );
    });
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

/// Runs [work] with a spinner and [what] ("Restoring…") over the screen, so a long restore or
/// lock never looks like a frozen app (review 7, P2-2/P2-4). The spinner always goes away, also
/// when [work] fails; its error is passed on.
Future<T> busyWhile<T>(BuildContext context, String what, Future<T> Function() work) async {
  final nav = Navigator.of(context, rootNavigator: true);
  var shown = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: C.card,
        content: Row(children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 16),
          Expanded(child: Text(what)),
        ]),
      ),
    ),
  ).whenComplete(() => shown = false);
  try {
    return await work();
  } finally {
    if (shown) nav.pop();
  }
}

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

/// A FutureBuilder that loads once per [cacheKey], not on every rebuild (review 2, P2-8): Progress
/// rebuilds on every tap, and re-reading the whole history each time was slow and flickered.
class CachedFuture<T> extends StatefulWidget {
  final Object cacheKey;
  final Future<T> Function() load;
  final AsyncWidgetBuilder<T> builder;
  const CachedFuture({super.key, required this.cacheKey, required this.load, required this.builder});
  @override
  State<CachedFuture<T>> createState() => _CachedFutureState<T>();
}

class _CachedFutureState<T> extends State<CachedFuture<T>> {
  Object? _key;
  Future<T>? _f;

  Future<T> _get() {
    if (_f == null || _key != widget.cacheKey) {
      _key = widget.cacheKey;
      _f = widget.load();
    }
    return _f!;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(future: _get(), builder: widget.builder);
}
