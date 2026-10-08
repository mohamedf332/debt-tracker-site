import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;

import 'package:debt_tracker/services/pdf_report_service.dart';
import 'package:debt_tracker/services/report_data.dart';

ReportTransaction _txn(
  int id,
  DateTime date,
  double amount,
  ReportTxnState state, {
  String? note,
  List<String> images = const [],
  double paid = 0,
  List<ReportPayment> payments = const [],
}) => ReportTransaction(
  id: id,
  date: date.toIso8601String(),
  amount: amount,
  state: state,
  note: note,
  imagePaths: images,
  // Settled rows are paid in full — the payment book is the source of truth.
  paid: paid > 0 ? paid : (state.isSettled ? amount : 0),
  payments: payments,
);

/// The report body used by every test below.
///
/// `photoPath == null` renders the exact same document with the attachment
/// column stripped, which is the control the cue assertions compare against.
List<ReportTransaction> _buildRows(String? photoPath) {
  final rows = <ReportTransaction>[
    for (var i = 1; i <= 47; i++)
      _txn(
        i,
        DateTime(2026, 1, 1 + (i % 27), i % 24, (i * 7) % 60),
        (i * 137).toDouble(),
        i.isEven
            ? ReportTxnState.theyOweMeUnsettled
            : (i % 3 == 0
                  ? ReportTxnState.iOweThemSettled
                  : ReportTxnState.iOweThemUnsettled),
        note: i % 4 == 0 ? 'ملاحظة رقم $i عن عملية شراء بضاعة من السوق' : null,
      ),
    _txn(
      900,
      DateTime(2026, 1, 15, 9, 30),
      750,
      ReportTxnState.theyOweMeUnsettled,
      note: 'مرفق صورة',
      images: photoPath == null ? const [] : [photoPath, photoPath],
    ),
    _txn(
      901,
      DateTime(2026, 1, 16, 10, 0),
      300,
      ReportTxnState.iOweThemSettled,
      images: photoPath == null ? const [] : ['$photoPath.missing'],
    ),
    _txn(
      902,
      DateTime(2026, 1, 20, 8, 0),
      1000,
      ReportTxnState.theyOweMeUnsettled,
      note: 'أثاث متعدد الدفعات',
      paid: 400,
      payments: [
        ReportPayment(date: DateTime(2026, 1, 22, 9, 0).toIso8601String(), amount: 250),
        ReportPayment(date: DateTime(2026, 1, 28, 11, 30).toIso8601String(), amount: 150),
      ],
    ),
  ]..sort((a, b) => a.date.compareTo(b.date));
  return rows;
}

ReportData _buildData(
  List<ReportTransaction> rows, {
  String? projectName = 'مشروع البيت',
  DateTime? from,
  DateTime? to,
}) => ReportData(
  personName: 'محمد أحمد',
  projectName: projectName,
  from: from,
  to: to,
  generatedAt: DateTime(2026, 9, 30, 14, 5),
  balance: 1850,
  totalTheyOweMe: 5200,
  totalIOweThem: 3350,
  budget: 10000,
  budgetRemaining: -450,
  unsettledReceivable: 2850,
  unsettledPayable: 1000,
  transactions: rows,
);

// ---------------------------------------------------------------------------
// A very small PDF reader: just enough structure and text to assert on.
//
// The report embeds two TrueType fonts. Each content stream paints text word
// by word as `[<glyphHex>]TJ` with the glyph ids resolved by the font's
// ToUnicode CMap, so we walk resources -> font -> ToUnicode and decode back
// to (presentation form) unicode.
// ---------------------------------------------------------------------------

String _latin(Uint8List bytes) => const Latin1Codec().decode(bytes);

List<String> _gotoDests(String pdf) => RegExp(
  r'/GoTo\s*/D\s*\(([^)]+)\)',
)
    .allMatches(pdf)
    .map((m) => m.group(1)!)
    .toList();

/// Destinations that actually exist in the document's name tree.
Set<String> _namedDests(String pdf) =>
    RegExp(r'\((tx_\d+|row_\d+)\)\s*<<')
        .allMatches(pdf)
        .map((m) => m.group(1)!)
        .toSet();

List<String> _decodeRuns(Uint8List bytes) {
  final pdf = _latin(bytes);

  String objBody(int n) {
    final i = pdf.indexOf('$n 0 obj');
    if (i < 0) return '';
    final j = pdf.indexOf('endobj', i);
    return pdf.substring(i, j < 0 ? i + 8000 : j);
  }

  String? objStream(int n) {
    final i = pdf.indexOf('$n 0 obj');
    if (i < 0) return null;
    final m = RegExp(r'stream\r?\n').firstMatch(pdf.substring(i));
    if (m == null) return null;
    final start = i + m.end;
    final end = pdf.indexOf('endstream', start);
    if (end < 0) return null;
    final raw = Uint8List.fromList(pdf.codeUnits.sublist(start, end));
    try {
      return utf8.decode(ZLibCodec().decode(raw), allowMalformed: true);
    } catch (_) {
      try {
        return utf8.decode(raw, allowMalformed: true);
      } catch (_) {
        return null;
      }
    }
  }

  final fontRes = <String, int>{};
  for (final m in RegExp(r'/Font\s*<<([^>]*)>>').allMatches(pdf)) {
    for (final f in RegExp(r'/(F\w+)\s+(\d+)\s+0\s+R').allMatches(m.group(1)!)) {
      fontRes[f.group(1)!] = int.parse(f.group(2)!);
    }
  }
  expect(fontRes, isNotEmpty, reason: 'report embeds no fonts');

  final glyphMaps = <String, Map<int, String>>{};
  for (final entry in fontRes.entries) {
    final toUni = RegExp(
      r'/ToUnicode\s+(\d+)\s+0\s+R',
    ).firstMatch(objBody(entry.value));
    if (toUni == null) continue;
    final cmap = objStream(int.parse(toUni.group(1)!));
    if (cmap == null) continue;
    final map = <int, String>{};
    for (final block
        in RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true).allMatches(cmap)) {
      for (final b in RegExp(
        r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
      ).allMatches(block.group(1)!)) {
        map[int.parse(b.group(1)!, radix: 16)] = String.fromCharCodes([
          for (var i = 0; i + 3 < b.group(2)!.length + 1; i += 4)
            int.parse(b.group(2)!.substring(i, i + 4), radix: 16),
        ]);
      }
    }
    for (final block
        in RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true).allMatches(cmap)) {
      for (final b in RegExp(
        r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
      ).allMatches(block.group(1)!)) {
        final lo = int.parse(b.group(1)!, radix: 16);
        final hi = int.parse(b.group(2)!, radix: 16);
        final dst = int.parse(b.group(3)!, radix: 16);
        for (var g = lo; g <= hi && g - lo < 500; g++) {
          map[g] = String.fromCharCode(dst + (g - lo));
        }
      }
    }
    glyphMaps[entry.key] = map;
  }
  expect(
    glyphMaps.values.any((m) => m.isNotEmpty),
    isTrue,
    reason: 'no ToUnicode cmap could be read',
  );

  final runs = <String>[];
  for (final m in RegExp(r'stream\r?\n').allMatches(pdf)) {
    final start = m.end;
    final end = pdf.indexOf('endstream', start);
    if (end < 0) continue;
    List<int> raw;
    try {
      raw = ZLibCodec().decode(Uint8List.fromList(pdf.codeUnits.sublist(start, end)));
    } catch (_) {
      continue;
    }
    String stream;
    try {
      stream = utf8.decode(raw, allowMalformed: true);
    } catch (_) {
      continue;
    }
    if (!stream.contains('Tf')) continue;

    var currentFont = '';
    for (final op in RegExp(
      r'/(F\w+)\s+[\d.]+\s+Tf|\[(.*?)\]\s*TJ|<([0-9A-Fa-f]+)>\s*Tj|\((.*?)\)\s*Tj',
      dotAll: true,
    ).allMatches(stream)) {
      if (op.group(1) != null) {
        currentFont = op.group(1)!;
        continue;
      }
      var hex = '';
      if (op.group(2) != null) {
        for (final h in RegExp(r'<([0-9A-Fa-f]+)>').allMatches(op.group(2)!)) {
          hex = hex + h.group(1)!;
        }
      } else {
        hex = op.group(3) ?? '';
      }
      if (hex.isEmpty) continue;
      final map = glyphMaps[currentFont] ?? const <int, String>{};
      final out = StringBuffer();
      for (var i = 0; i + 3 < hex.length + 1; i += 4) {
        final g = int.tryParse(
          hex.substring(i, (i + 4).clamp(0, hex.length)),
          radix: 16,
        );
        if (g != null) out.write(map[g] ?? '');
      }
      runs.add(out.toString());
    }
  }
  expect(runs, isNotEmpty, reason: 'no painted text found in the report');
  return runs;
}

/// The attachment cue is painted as its own word runs: `صور` `(2)` `-` `في`
/// …, while the payments label ends on `(2)` with no dash after it. The
/// `(count)` + `-` pair is therefore the label's fingerprint.
List<String> _cueCounts(Uint8List bytes) {
  final runs = _decodeRuns(bytes);
  final counts = <String>[];
  for (var i = 0; i + 1 < runs.length; i++) {
    final m = RegExp(r'^\((\d+)\)$').firstMatch(runs[i]);
    if (m != null && runs[i + 1] == '-') counts.add(m.group(1)!);
  }
  return counts;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renderReport produces a multi page RTL report with appendix', () async {
    final workDir = Directory.systemTemp.createTempSync('pdf_report_test');
    addTearDown(() => workDir.deleteSync(recursive: true));

    // Two real photos so the appendix path is exercised end to end.
    final photo = im.Image(width: 1200, height: 800);
    im.fill(photo, color: im.ColorRgb8(30, 120, 200));
    final photoPath = '${workDir.path}/photo1.jpg';
    File(photoPath).writeAsBytesSync(im.encodeJpg(photo));

    final bytes = await renderReport(
      _buildData(_buildRows(photoPath)),
    );
    expect(bytes, isA<Uint8List>());
    expect(bytes.length, greaterThan(8000));
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');

    final out = File('/tmp/opencode/report_test.pdf');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('wrote ${out.path} (${bytes.length} bytes)');
  });

  test('rows with photos link into the appendix and back again', () async {
    final workDir = Directory.systemTemp.createTempSync('pdf_links_test');
    addTearDown(() => workDir.deleteSync(recursive: true));

    final photo = im.Image(width: 600, height: 400);
    im.fill(photo, color: im.ColorRgb8(10, 90, 180));
    final photoPath = '${workDir.path}/photo.jpg';
    File(photoPath).writeAsBytesSync(im.encodeJpg(photo));

    final bytes = await renderReport(_buildData(_buildRows(photoPath)));
    final pdf = _latin(bytes);

    final gotos = _gotoDests(pdf);
    final forward = gotos.where((d) => d.startsWith('tx_')).toList();
    final back = gotos.where((d) => d.startsWith('row_')).toList();

    // Only the two transactions that carry attachments are tappable, and
    // every cell of those rows is (a table row cannot be a link itself).
    expect(forward, hasLength(8), reason: '4 cells x 2 rows, got: $forward');
    expect(forward.where((d) => d == 'tx_900'), hasLength(4));
    expect(forward.where((d) => d == 'tx_901'), hasLength(4));
    expect(forward.where((d) => d.startsWith('tx_902')), isEmpty);
    expect(forward.where((d) => d.startsWith('tx_1')), isEmpty);

    // One back link per appendix block, including the missing-photo one.
    expect(back, hasLength(2), reason: 'got: $back');
    expect(back.where((d) => d == 'row_900'), hasLength(1));
    expect(back.where((d) => d == 'row_901'), hasLength(1));

    // Every link resolves to a destination that exists in the name tree.
    final named = _namedDests(pdf);
    expect(named, containsAll(<String>{...forward, ...back}));

    // And the name tree itself is exactly what the two rows need — no
    // orphan anchors for transactions that have no photos.
    expect(named, <String>{'tx_900', 'tx_901', 'row_900', 'row_901'});
  });

  test('only transactions with photos print the attachment cue', () async {
    final workDir = Directory.systemTemp.createTempSync('pdf_cue_test');
    addTearDown(() => workDir.deleteSync(recursive: true));

    final photo = im.Image(width: 600, height: 400);
    im.fill(photo, color: im.ColorRgb8(10, 90, 180));
    final photoPath = '${workDir.path}/photo.jpg';
    File(photoPath).writeAsBytesSync(im.encodeJpg(photo));

    // Same document, attachment column stripped: the control.
    final withoutPhotos = await renderReport(_buildData(_buildRows(null)));
    final withPhotos = await renderReport(_buildData(_buildRows(photoPath)));

    expect(_cueCounts(withPhotos), <String>['2', '1']);
    expect(_cueCounts(withoutPhotos), isEmpty);

    // …and it sits in the table, not only in the appendix: both documents
    // paint identical text up to the first row that carries photos. Page
    // counters are dropped — they are the only runs made of plain ASCII
    // digits (everything else is Arabic-Indic) and the two documents have a
    // different page count.
    List<String> painted(Uint8List bytes) => _decodeRuns(bytes)
        .where((r) => !RegExp(r'^\d+$').hasMatch(r))
        .toList();
    final runsWith = painted(withPhotos);
    final runsWithout = painted(withoutPhotos);
    // The cue paints as `صور` `(2)` `-` `في` `الملحق`, so its first run sits
    // right before the count.
    var indexOfCue = -1;
    for (var i = 1; i + 1 < runsWith.length; i++) {
      if (RegExp(r'^\(\d+\)$').hasMatch(runsWith[i]) &&
          runsWith[i + 1] == '-') {
        indexOfCue = i - 1;
        break;
      }
    }
    expect(indexOfCue, greaterThanOrEqualTo(0));
    expect(
      runsWith.sublist(0, indexOfCue),
      runsWithout.sublist(0, indexOfCue),
      reason: 'the cue is inserted inside the table, not appended at the end',
    );
  });

  test('links hold for a person wide report and a custom date range', () async {
    final workDir = Directory.systemTemp.createTempSync('pdf_scope_test');
    addTearDown(() => workDir.deleteSync(recursive: true));

    final photo = im.Image(width: 600, height: 400);
    im.fill(photo, color: im.ColorRgb8(10, 90, 180));
    final photoPath = '${workDir.path}/photo.jpg';
    File(photoPath).writeAsBytesSync(im.encodeJpg(photo));

    for (final data in <ReportData>[
      // Whole project, whole period.
      _buildData(
        _buildRows(photoPath),
        projectName: null,
        from: null,
        to: null,
      ),
      // Person wide, narrowed range.
      _buildData(
        _buildRows(photoPath),
        projectName: 'مشروع آخر',
        from: DateTime(2026, 1, 10),
        to: DateTime(2026, 1, 20),
      ),
    ]) {
      final bytes = await renderReport(data);
      final pdf = _latin(bytes);
      final forward = _gotoDests(pdf).where((d) => d.startsWith('tx_')).toSet();
      expect(forward, <String>{'tx_900', 'tx_901'});
      expect(_namedDests(pdf), containsAll(<String>{...forward, 'row_900'}));
      expect(_cueCounts(bytes), hasLength(2));
    }
  });
}
