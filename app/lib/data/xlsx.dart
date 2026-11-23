import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A plain Excel file (.xlsx) from sheets of rows (batch 20, F316): Excel, LibreOffice, Google
/// Sheets and Numbers open it. Cells that read as a number are written as numbers; the first row
/// of each sheet is bold-free headers (no styles needed).
Uint8List xlsx(Map<String, List<List<String>>> sheets) {
  final a = Archive();
  void add(String name, String text) {
    final b = utf8.encode(text);
    a.addFile(ArchiveFile(name, b.length, b));
  }

  final names = [for (final n in sheets.keys) _sheetName(n)];
  add('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '${[for (var i = 1; i <= names.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
      '</Types>');
  add('_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>');
  add('xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
      '${[for (var i = 0; i < names.length; i++) '<sheet name="${_x(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
      '</sheets></workbook>');
  add('xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '${[for (var i = 1; i <= names.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
      '</Relationships>');
  var i = 0;
  for (final rows in sheets.values) {
    i++;
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
    for (var r = 0; r < rows.length; r++) {
      b.write('<row r="${r + 1}">');
      for (var c = 0; c < rows[r].length; c++) {
        final v = rows[r][c];
        final ref = '${_col(c)}${r + 1}';
        final n = r == 0 ? null : _number(v);
        if (n != null) {
          b.write('<c r="$ref"><v>$n</v></c>');
        } else if (v.isNotEmpty) {
          b.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${_x(v)}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    add('xl/worksheets/sheet$i.xml', b.toString());
  }
  return Uint8List.fromList(ZipEncoder().encode(a));
}

String _col(int c) {
  var s = '';
  var n = c + 1;
  while (n > 0) {
    final m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

/// A plain number ("102.5", "-3", "5"), not ids with leading zeros or dates.
String? _number(String v) => RegExp(r'^-?(0|[1-9]\d{0,14})(\.\d+)?$').hasMatch(v) ? v : null;

String _sheetName(String n) => n.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').substring(0, n.length.clamp(0, 31));

String _x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
