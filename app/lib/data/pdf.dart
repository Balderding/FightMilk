import 'dart:convert';
import 'dart:typed_data';

/// A small PDF writer for the report and the printable plan (batch 20, F317, F328): A4 pages
/// with text in Helvetica, lines and boxes. No package, no fonts to ship. Coordinates are in
/// points from the top-left corner.
class PdfDoc {
  static const w = 595.0, h = 842.0; // A4
  final _pages = <StringBuffer>[];
  final String title;
  PdfDoc(this.title);

  PdfPage page() {
    final b = StringBuffer();
    _pages.add(b);
    return PdfPage._(b);
  }

  int get pages => _pages.length;

  Uint8List bytes() {
    final objs = <String>[];
    // 1 catalog, 2 pages, 3 font, 4 bold font, 5 info, then a page + content pair per page
    final kids = [for (var i = 0; i < _pages.length; i++) '${6 + i * 2} 0 R'].join(' ');
    objs.add('<< /Type /Catalog /Pages 2 0 R >>');
    objs.add('<< /Type /Pages /Kids [$kids] /Count ${_pages.length} >>');
    objs.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
    objs.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>');
    objs.add('<< /Title (${_esc(title)}) /Producer (FightMilk) >>');
    for (var i = 0; i < _pages.length; i++) {
      final content = latin1.encode(_pages[i].toString());
      objs.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $w $h] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ${7 + i * 2} 0 R >>');
      objs.add('<< /Length ${content.length} >>\nstream\n${latin1.decode(content)}\nendstream');
    }
    final out = BytesBuilder();
    void put(String s) => out.add(latin1.encode(s));
    put('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
    final offsets = <int>[];
    for (var i = 0; i < objs.length; i++) {
      offsets.add(out.length);
      put('${i + 1} 0 obj\n${objs[i]}\nendobj\n');
    }
    final xref = out.length;
    put('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
    for (final o in offsets) {
      put('${o.toString().padLeft(10, '0')} 00000 n \n');
    }
    put('trailer\n<< /Size ${objs.length + 1} /Root 1 0 R /Info 5 0 R >>\nstartxref\n$xref\n%%EOF\n');
    return out.toBytes();
  }
}

class PdfPage {
  final StringBuffer _b;
  PdfPage._(this._b);

  String _n(double v) => v.toStringAsFixed(2);

  void text(double x, double y, String s, {double size = 10, bool bold = false, double gray = 0}) {
    _b.write('BT /${bold ? 'F2' : 'F1'} ${_n(size)} Tf ${_n(gray)} g ${_n(x)} ${_n(PdfDoc.h - y)} Td (${_esc(s)}) Tj ET\n');
  }

  void line(double x1, double y1, double x2, double y2, {double width = 0.5, double gray = 0}) {
    _b.write('${_n(gray)} G ${_n(width)} w ${_n(x1)} ${_n(PdfDoc.h - y1)} m ${_n(x2)} ${_n(PdfDoc.h - y2)} l S\n');
  }

  void box(double x, double y, double w, double h, {double width = 0.5, double gray = 0, double? fill}) {
    final r = '${_n(x)} ${_n(PdfDoc.h - y - h)} ${_n(w)} ${_n(h)} re';
    if (fill != null) _b.write('${_n(fill)} g $r f\n');
    _b.write('${_n(gray)} G ${_n(width)} w $r S\n');
  }

  /// A polyline through [pts] (already in page points).
  void path(List<(double, double)> pts, {double width = 1, double gray = 0}) {
    if (pts.length < 2) return;
    _b.write('${_n(gray)} G ${_n(width)} w ${_n(pts.first.$1)} ${_n(PdfDoc.h - pts.first.$2)} m ');
    for (final p in pts.skip(1)) {
      _b.write('${_n(p.$1)} ${_n(PdfDoc.h - p.$2)} l ');
    }
    _b.write('S\n');
  }
}

/// Text for a WinAnsi Helvetica string: PDF escapes, and characters outside Latin-1 swapped for
/// plain ones (× → x, – → -, … → ...).
String _esc(String s) {
  final t = s
      .replaceAll('×', 'x')
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('−', '-')
      .replaceAll('…', '...')
      .replaceAll('→', '->')
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('·', '-');
  final b = StringBuffer();
  for (final c in t.runes) {
    if (c == 0x5C || c == 0x28 || c == 0x29) {
      b.write('\\${String.fromCharCode(c)}');
    } else if (c < 32 || c > 255) {
      b.write(c > 255 ? '?' : ' ');
    } else {
      b.writeCharCode(c);
    }
  }
  return b.toString();
}

/// Cuts [s] to about [chars] characters for a table cell.
String fit(String s, int chars) => s.length <= chars ? s : '${s.substring(0, chars - 1)}.';
