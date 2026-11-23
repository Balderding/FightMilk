import 'package:flutter/material.dart';

import '../domain/plates.dart';
import '../domain/units.dart';
import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// 1RM, rep maxes, % of 1RM, RPE chart, plates per side and kg/lb, all on the phone.
class CalculatorsScreen extends StatefulWidget {
  final AppState s;
  const CalculatorsScreen({super.key, required this.s});
  @override
  State<CalculatorsScreen> createState() => _CalculatorsScreenState();
}

class _CalculatorsScreenState extends State<CalculatorsScreen> {
  final w = TextEditingController(text: '');
  final r = TextEditingController(text: '5');
  final total = TextEditingController(text: '');
  final conv = TextEditingController(text: '');

  double? _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.'));

  Widget _field(TextEditingController c, String label, {String? suffix}) => SizedBox(
        width: 140,
        child: TextField(
          enableIMEPersonalizedLearning: false,
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, suffixText: suffix),
          onChanged: (_) => setState(() {}),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final u = s.unit;
    final ul = unitLabel(u);
    final wv = _num(w), rv = _num(r)?.round();
    final one = (wv != null && rv != null && rv > 0) ? e1rm(fromUnit(wv, u), rv) : null;
    final tv = _num(total);
    final ps = s.plateSetup;
    final cv = _num(conv);
    return Scaffold(
      appBar: AppBar(title: const Text('Calculators')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('One-rep max', style: TextStyle(fontWeight: FontWeight.w600)),
              const Dim('Weight and reps of a hard set; the app estimates the rest.', size: 12),
              Wrap(spacing: 12, children: [_field(w, 'Weight', suffix: ul), _field(r, 'Reps')]),
              if (one != null) ...[
                const SizedBox(height: 8),
                Text('Estimated 1RM: ${fmtWeight(one, u)} $ul', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.gold)),
                const SizedBox(height: 6),
                const Text('Rep maxes', style: TextStyle(fontWeight: FontWeight.w600)),
                Wrap(spacing: 14, runSpacing: 4, children: [
                  for (final n in const [1, 2, 3, 4, 5, 6, 8, 10, 12, 15]) Text('$n× ${fmtWeight(weightForReps(one, n), u)}'),
                ]),
                const SizedBox(height: 6),
                const Text('% of 1RM', style: TextStyle(fontWeight: FontWeight.w600)),
                Wrap(spacing: 14, runSpacing: 4, children: [
                  for (final pc in const [50, 60, 65, 70, 75, 80, 85, 90, 95]) Text('$pc% ${fmtWeight(one * pc / 100, u)}'),
                ]),
                const SizedBox(height: 6),
                const Text('RPE chart (weight for reps at RPE)', style: TextStyle(fontWeight: FontWeight.w600)),
                const Dim('RPE = how hard: 10 = not one more rep, 9 = one left, 8 = two left.', size: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 14,
                    headingRowHeight: 32,
                    dataRowMinHeight: 28,
                    dataRowMaxHeight: 30,
                    columns: [const DataColumn(label: Text('Reps')), for (final rp in const [10.0, 9.0, 8.0, 7.0, 6.0]) DataColumn(label: Text('RPE ${rp.toStringAsFixed(0)}'))],
                    rows: [
                      for (final n in const [1, 2, 3, 4, 5, 6, 8, 10])
                        DataRow(cells: [DataCell(Text('$n')), for (final rp in const [10.0, 9.0, 8.0, 7.0, 6.0]) DataCell(Text(fmtWeight(one * rpePercent(n, rp) / 100, u)))]),
                    ],
                  ),
                ),
              ],
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Plates per side', style: TextStyle(fontWeight: FontWeight.w600)),
              Dim('Bar ${fmtWeight(ps.bar, u)} $ul, plates ${ps.plates.map(fmtNum).join(', ')} (from ${s.activeGym?.name ?? 'the standard set'})', size: 12),
              _field(total, 'Total', suffix: ul),
              if (tv != null && tv > 0) ...[
                const SizedBox(height: 6),
                Builder(builder: (c) {
                  final (pl, made) = platesFor(fromUnit(tv, u), ps.bar, ps.plates, u);
                  return Text('Per side: ${platesText(pl)}${(made - fromUnit(tv, u)).abs() > 0.05 ? '  (closest: ${fmtWeight(made, u)} $ul)' : ''}', style: const TextStyle(fontSize: 16, color: C.teal));
                }),
              ],
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('kg ↔ lb', style: TextStyle(fontWeight: FontWeight.w600)),
              _field(conv, 'Weight'),
              if (cv != null) ...[
                const SizedBox(height: 6),
                Text('${fmtNum(cv)} kg = ${fmtNum(kgToLb(cv))} lb'),
                Text('${fmtNum(cv)} lb = ${fmtNum(lbToKg(cv))} kg'),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
