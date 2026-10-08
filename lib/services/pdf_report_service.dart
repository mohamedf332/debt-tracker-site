import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as im;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../theme/app_colors.dart';
import '../utils/currency_formatter.dart';
import '../utils/date_formatter.dart';
import 'report_data.dart';
import 'report_data_builder.dart';

/// Print/export entry point for the person and project reports.
///
/// The caller only ever asks for a report by scope + optional date range; the
/// heavy lifting is split in two:
///
///  * [ReportDataBuilder] reads the database (main isolate),
///  * [renderReport] turns the frozen [ReportData] into PDF bytes on a
///    background isolate — it never touches the database.
class PdfReportService {
  PdfReportService._();

  static final PdfReportService instance = PdfReportService._();

  // Cairo (bundled, not PdfGoogleFonts): Tajawal has no U+066C thousands
  // separator, which [CurrencyFormatter] emits, so it renders as tofu.
  static const String regularAsset = 'assets/fonts/Cairo-Regular.ttf';
  static const String boldAsset = 'assets/fonts/Cairo-Bold.ttf';

  final ReportDataBuilder _builder = ReportDataBuilder();

  /// Person-wide report: every project plus the transactions without one.
  ///
  /// `null` means there is nothing to report on (unknown person).
  Future<ReportPdf?> buildPersonReport({
    required int personId,
    required DateTime? startDate,
    required DateTime? endDate,
  }) async {
    final data = await _builder.buildPersonReport(
      personId: personId,
      startDate: startDate,
      endDate: endDate,
    );
    if (data == null) return null;
    return ReportPdf(await renderReport(data), _fileName(data));
  }

  /// Report for a single project, including its budget when it has one.
  Future<ReportPdf?> buildProjectReport({
    required int projectId,
    required DateTime? startDate,
    required DateTime? endDate,
  }) async {
    final data = await _builder.buildProjectReport(
      projectId: projectId,
      startDate: startDate,
      endDate: endDate,
    );
    if (data == null) return null;
    return ReportPdf(await renderReport(data), _fileName(data));
  }

  /// Drops [report] in the temp directory and hands it to the platform's
  /// "open with" chooser. Only a real PDF reader follows the in-document
  /// links — the in-app preview rasterizes every page.
  Future<void> openExternally(ReportPdf report) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, report.fileName));
    await file.writeAsBytes(report.bytes, flush: true);
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw StateError(
        result.message.isEmpty ? 'تعذّر فتح الملف' : result.message,
      );
    }
  }

  /// Saves / sends the file through the system share sheet.
  Future<void> share(ReportPdf report) => Printing.sharePdf(
    bytes: report.bytes,
    filename: report.fileName,
  );

  static String _fileName(ReportData data) {
    final scope = data.projectName == null
        ? data.personName
        : '${data.personName}_${data.projectName}';
    return 'كشف_حساب_${scope}_${DateFormatter.formatDate(DateTime.now())}.pdf';
  }
}

/// A finished report: the bytes plus the name it is shared and opened under.
class ReportPdf {
  const ReportPdf(this.bytes, this.fileName);

  final Uint8List bytes;
  final String fileName;
}

// ------------------------------------------------------------------ render

/// Pure rendering: [ReportData] in, PDF bytes out.
///
/// Runs on a background isolate so a report with photos never blocks the UI.
/// The fonts are read through [rootBundle] here because a spawned isolate
/// has no asset messenger of its own; everything else (including the images)
/// is read inside the isolate, one transaction at a time.
Future<Uint8List> renderReport(ReportData data) async {
  final regular = await _loadFont(PdfReportService.regularAsset);
  final bold = await _loadFont(PdfReportService.boldAsset);
  final job = _RenderJob(data: data, regular: regular, bold: bold);
  return Isolate.run(() => _render(job));
}

Future<ByteData> _loadFont(String asset) async {
  final loaded = await rootBundle.load(asset);
  final copy = Uint8List.fromList(
    loaded.buffer.asUint8List(loaded.offsetInBytes, loaded.lengthInBytes),
  );
  return copy.buffer.asByteData();
}

class _RenderJob {
  const _RenderJob({
    required this.data,
    required this.regular,
    required this.bold,
  });

  final ReportData data;
  final ByteData regular;
  final ByteData bold;
}

Future<Uint8List> _render(_RenderJob job) async {
  // Fresh isolate, fresh locale tables — without this every DateFormat below
  // throws LocaleDataException.
  await initializeDateFormatting('ar_EG', null);
  return _ReportDocument(job.data, job.regular, job.bold).build();
}

// -------------------------------------------------------------- document

class _ReportDocument {
  _ReportDocument(this.data, ByteData regular, ByteData bold)
    : _regularFont = pw.Font.ttf(regular),
      _boldFont = pw.Font.ttf(bold);

  static const double _pageMargin = 32;
  static const double _footerHeight = 22;
  static const double _maxPageImageHeight = 320;
  static const int _imageLongSide = 1600;
  static const int _imageQuality = 75;

  static final DateFormat _date = DateFormat('dd/MM/yyyy', 'ar_EG');

  static final PdfColor _primary = _fromApp(AppColors.primary.toARGB32());
  static final PdfColor _primaryDark = _fromApp(AppColors.primaryDark.toARGB32());
  static final PdfColor _ink = _fromApp(AppColors.dark.toARGB32());
  static final PdfColor _gray = _fromApp(AppColors.gray.toARGB32());
  static final PdfColor _muted = PdfColor.fromInt(
    softenTowardWhite(AppColors.gray.toARGB32(), 0.35),
  );
  static final PdfColor _green = _fromApp(AppColors.green.toARGB32());
  static final PdfColor _red = _fromApp(AppColors.red.toARGB32());
  static final PdfColor _border = _fromApp(AppColors.border.toARGB32());
  static final PdfColor _surface = _fromApp(AppColors.lightGrayBg.toARGB32());
  static final PdfColor _onPrimary = PdfColor.fromInt(
    withAlpha(AppColors.white.toARGB32(), 0xE6),
  );
  static final PdfColor _onPrimarySoft = PdfColor.fromInt(
    withAlpha(AppColors.white.toARGB32(), 0xCC),
  );

  final ReportData data;
  final pw.Font _regularFont;
  final pw.Font _boldFont;

  static PdfColor _fromApp(int argb) => PdfColor.fromInt(argb);

  double get _contentWidth => PdfPageFormat.a4.width - 2 * _pageMargin;

  double get _contentHeight =>
      PdfPageFormat.a4.height - 2 * _pageMargin - _footerHeight;

  // ------------------------------------------------------------------ api

  Future<Uint8List> build() async {
    final appendix = await _buildAppendix();

    final doc = pw.Document(
      title: data.projectName == null
          ? 'كشف حساب ${data.personName}'
          : 'كشف حساب ${data.personName} - ${data.projectName}',
      author: 'دفتر الديون',
      creator: 'دفتر الديون',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(_pageMargin),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: _regularFont, bold: _boldFont),
        // The default is 20; a long report trips PdfTooBigPageException.
        maxPages: 500,
        footer: _buildFooter,
        build: (context) => <pw.Widget>[
          ..._buildHeader(),
          pw.SizedBox(height: 16),
          ..._buildSummaryPage(),
          // The summary owns page 1 on its own; the table starts clean.
          pw.NewPage(),
          ..._buildTransactionsTable(),
          ...appendix,
        ],
      ),
    );

    return doc.save();
  }

  pw.TextStyle _style(double size, {bool bold = false, PdfColor? color}) {
    return pw.TextStyle(
      fontSize: size,
      font: bold ? _boldFont : _regularFont,
      color: color ?? _ink,
    );
  }

  // ---------------------------------------------------------------- header

  List<pw.Widget> _buildHeader() {
    return [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.fromLTRB(18, 15, 18, 15),
        decoration: pw.BoxDecoration(
          color: _primary,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('كشف حساب', style: _style(10.5, color: _onPrimarySoft)),
            pw.SizedBox(height: 4),
            pw.Text(
              data.projectName == null
                  ? data.personName
                  : '${data.personName} - ${data.projectName}',
              style: _style(19, bold: true, color: PdfColors.white),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              children: [
                pw.Text(
                  _periodLabel(),
                  style: _style(10.5, bold: true, color: _onPrimary),
                ),
                pw.SizedBox(width: 14),
                pw.Text(
                  'تاريخ الإصدار: ${_date.format(data.generatedAt)}',
                  style: _style(10.5, color: _onPrimarySoft),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  String _periodLabel() {
    if (data.from == null && data.to == null) return 'كل الفترة';
    final from = data.from == null ? 'البداية' : _date.format(data.from!);
    final to = data.to == null ? 'النهاية' : _date.format(data.to!);
    return 'من $from إلى $to';
  }

  // -------------------------------------------------------------- summary

  List<pw.Widget> _buildSummaryPage() {
    // Every card is forced to stay whole: a spannable Column would otherwise
    // be sliced through the middle the moment the page gets tight.
    return [
      _atomic(_buildBalanceCard()),
      pw.SizedBox(height: 12),
      _atomic(_buildDirectionalCards()),
      if (data.budget != null && data.budgetRemaining != null) ...[
        pw.SizedBox(height: 12),
        _atomic(_buildBudgetBlock()),
      ],
      pw.SizedBox(height: 12),
      _atomic(_buildUnsettledBlock()),
    ];
  }

  /// Wraps [child] so MultiPage moves it to the next page instead of splitting
  /// it across the boundary.
  pw.Widget _atomic(pw.Widget child) =>
      pw.Inseparable(canSpan: false, child: child);

  pw.Widget _buildBalanceCard() {
    final balance = data.balance;
    final color = balance > 0
        ? _green
        : balance < 0
            ? _red
            : _gray;
    final caption = balance > 0
        ? 'مستحق لي'
        : balance < 0
            ? 'مستحق عليه'
            : 'متصافيين';

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _surface,
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('الرصيد الحالي', style: _style(11, color: _gray)),
          pw.SizedBox(height: 6),
          pw.Text(
            CurrencyFormatter.format(balance),
            style: _style(26, bold: true, color: color),
          ),
          pw.SizedBox(height: 4),
          pw.Text(caption, style: _style(10, color: _muted)),
        ],
      ),
    );
  }

  pw.Widget _buildDirectionalCards() {
    return pw.Row(
      children: [
        pw.Expanded(
          child: _statCard('إجمالي ليَّ عنده', data.totalTheyOweMe, _green),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _statCard('إجمالي عليّا له', data.totalIOweThem, _red),
        ),
      ],
    );
  }

  pw.Widget _statCard(String label, double value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: _style(10.5, color: _gray)),
          pw.SizedBox(height: 5),
          pw.Text(
            CurrencyFormatter.format(value),
            style: _style(16, bold: true, color: color),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildBudgetBlock() {
    final budget = data.budget!;
    final remaining = data.budgetRemaining!;
    final spent = budget - remaining;
    final ratio = budget <= 0
        ? 1.0
        : (spent / budget).clamp(0.0, 1.0).toDouble();
    final spentUnits = (ratio * 100).round().clamp(0, 100);
    final overBudget = remaining < 0;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('البادجت', style: _style(12, bold: true, color: _ink)),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pw.Expanded(
                child: _budgetValue(
                  'الميزانية الأصلية',
                  CurrencyFormatter.format(budget),
                  _primaryDark,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _budgetValue(
                  'المتبقي',
                  CurrencyFormatter.format(remaining),
                  overBudget ? _red : _green,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              if (spentUnits > 0)
                pw.Expanded(
                  flex: spentUnits,
                  child: pw.Container(
                    height: 8,
                    decoration: pw.BoxDecoration(
                      color: overBudget ? _red : _primary,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                  ),
                ),
              if (spentUnits < 100)
                pw.Expanded(
                  flex: 100 - spentUnits,
                  child: pw.Container(
                    height: 8,
                    decoration: pw.BoxDecoration(
                      color: _border,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _budgetValue(String label, String value, PdfColor color) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: _style(10, color: _gray)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: _style(14, bold: true, color: color)),
      ],
    );
  }

  pw.Widget _buildUnsettledBlock() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _surface,
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('مستحقات غير مسدَّدة', style: _style(12, bold: true, color: _ink)),
          pw.SizedBox(height: 9),
          _unsettledRow(
            'مستحق لي ولم يُحصَّل بعد',
            data.unsettledReceivable,
            _green,
          ),
          pw.SizedBox(height: 7),
          _unsettledRow(
            'مستحق عليَّ ولم أسدَّد بعد',
            data.unsettledPayable,
            _red,
          ),
        ],
      ),
    );
  }

  pw.Widget _unsettledRow(String label, double value, PdfColor color) {
    return pw.Row(
      children: [
        pw.Expanded(child: pw.Text(label, style: _style(11, color: _ink))),
        pw.Text(
          CurrencyFormatter.format(value),
          style: _style(12, bold: true, color: color),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- table

  List<pw.Widget> _buildTransactionsTable() {
    return [
      pw.SizedBox(height: 4),
      _buildSectionTitle('المعاملات', data.transactions.length),
      if (data.isEmpty)
        _buildEmptyState()
      else
        // Must stay a direct child of MultiPage.build: only then does it
        // paginate and repeat its header row.
        _buildTable(),
    ];
  }

  pw.Widget _buildSectionTitle(String title, int count) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _border, width: 1)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(title, style: _style(14, bold: true))),
          pw.Text('عدد المعاملات: $count', style: _style(10, color: _muted)),
        ],
      ),
    );
  }

  pw.Widget _buildEmptyState() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 30),
      decoration: pw.BoxDecoration(
        color: _surface,
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Text(
        'لا توجد معاملات في هذه الفترة',
        style: _style(12, color: _gray),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  /// Column order is left-to-right: the table engine never mirrors itself, so
  /// a report read right-to-left starts at the right-most column (التاريخ).
  pw.Widget _buildTable() {
    const line = 0.5;
    final border = pw.BorderSide(color: _border, width: line);

    return pw.Table(
      border: pw.TableBorder(
        top: border,
        bottom: border,
        left: border,
        right: border,
        horizontalInside: border,
        verticalInside: border,
      ),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(1),
        1: pw.FixedColumnWidth(66),
        2: pw.FixedColumnWidth(88),
        3: pw.FixedColumnWidth(76),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          repeat: true,
          children: [
            _headerCell('البيان', align: pw.TextAlign.start),
            _headerCell('النوع'),
            _headerCell('المبلغ'),
            _headerCell('التاريخ'),
          ],
        ),
        for (var i = 0; i < data.transactions.length; i++)
          _dataRow(data.transactions[i], i),
      ],
    );
  }

  pw.Widget _headerCell(String title, {pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: pw.BoxDecoration(color: _primary),
      child: pw.Text(
        title,
        style: _style(10, bold: true, color: PdfColors.white),
        textAlign: align,
      ),
    );
  }

  /// One row of the transactions table.
  ///
  /// Rows that carry photos are tappable end to end: a [pw.TableRow] cannot
  /// be wrapped as a whole, so each cell's content becomes its own link to
  /// the appendix section of that transaction (`tx_<id>`). The first cell
  /// also carries the `row_<id>` anchor the section's back link lands on.
  /// Rows without photos are plain — no link, no cue.
  pw.TableRow _dataRow(ReportTransaction txn, int index) {
    final bg = index.isEven ? PdfColors.white : _surface;
    final cells = <pw.Widget>[
      _noteCell(txn, bg),
      _typeCell(txn, bg),
      _amountCell(txn, bg),
      _dateCell(txn, bg),
    ];

    if (txn.imagePaths.isEmpty) return pw.TableRow(children: cells);

    return pw.TableRow(
      children: [
        for (var i = 0; i < cells.length; i++)
          pw.Link(
            destination: 'tx_${txn.id}',
            child: i == 0
                ? pw.Anchor(name: 'row_${txn.id}', child: cells[i])
                : cells[i],
          ),
      ],
    );
  }

  pw.Widget _cellBox(PdfColor bg, pw.Widget child) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: pw.BoxDecoration(color: bg),
      child: child,
    );
  }

  /// The description column: the note, and — for an installment row — what
  /// has been paid plus the full list of installments beneath it.
  ///
  /// The table has no colspan, so everything about a partial row that is not
  /// money or a date lives in this one cell.
  pw.Widget _noteCell(ReportTransaction txn, PdfColor bg) {
    final note = txn.note?.trim() ?? '';
    final children = <pw.Widget>[
      pw.Text(
        note.isEmpty ? '—' : note,
        style: _style(10, color: note.isEmpty ? _muted : _ink),
        textAlign: pw.TextAlign.start,
      ),
    ];

    if (txn.isPartlyPaid) {
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.Text(
            'مدفوع ${CurrencyFormatter.format(txn.paid)} من '
            '${CurrencyFormatter.format(txn.amount)}',
            style: _style(8.5, color: _muted),
            textAlign: pw.TextAlign.start,
          ),
        ),
      );
    }

    if (txn.imagePaths.isNotEmpty) {
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.Text(
            'صور (${txn.imagePaths.length}) - في الملحق',
            style: _style(8, color: _primaryDark).copyWith(
              decoration: pw.TextDecoration.underline,
              decorationColor: _primaryDark,
            ),
            textAlign: pw.TextAlign.start,
          ),
        ),
      );
    }

    if (txn.payments.isNotEmpty) {
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'الدفعات (${txn.payments.length})',
                style: _style(8, bold: true, color: _muted),
                textAlign: pw.TextAlign.start,
              ),
              for (final payment in txn.payments)
                pw.Padding(
                  padding: const pw.EdgeInsetsDirectional.only(start: 8),
                  child: pw.Text(
                    '${_date.format(DateTime.parse(payment.date))} — '
                    '${CurrencyFormatter.format(payment.amount)}',
                    style: _style(8, color: _muted),
                    textAlign: pw.TextAlign.start,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return _cellBox(
      bg,
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: children,
      ),
    );
  }

  pw.Widget _typeCell(ReportTransaction txn, PdfColor bg) {
    return _cellBox(
      bg,
      pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            typeLabelAr(txn.state),
            style: _style(10, color: typeColor(txn.state)),
            textAlign: pw.TextAlign.center,
          ),
          if (txn.isPartlyPaid)
            pw.Text(
              'جزئي',
              style: _style(7.5, color: _muted),
              textAlign: pw.TextAlign.center,
            ),
        ],
      ),
    );
  }

  pw.Widget _amountCell(ReportTransaction txn, PdfColor bg) {
    return _cellBox(
      bg,
      pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            CurrencyFormatter.format(txn.amount),
            style: _style(10.5, bold: true, color: typeColor(txn.state)),
            textAlign: pw.TextAlign.center,
          ),
          if (txn.isPartlyPaid)
            pw.Text(
              'المتبقي ${CurrencyFormatter.format(txn.remaining)}',
              style: _style(8, color: _muted),
              textAlign: pw.TextAlign.center,
            ),
        ],
      ),
    );
  }

  pw.Widget _dateCell(ReportTransaction txn, PdfColor bg) {
    final text = _date.format(DateTime.parse(txn.date));
    return _cellBox(
      bg,
      pw.Text(text, style: _style(10, color: _ink), textAlign: pw.TextAlign.center),
    );
  }

  // -------------------------------------------------------------- appendix

  /// Reads every attachment one transaction at a time, keeps only a compact
  /// JPEG, and hands back widgets that are never allowed to split across pages.
  Future<List<pw.Widget>> _buildAppendix() async {
    final withImages = data.transactions
        .where((txn) => txn.imagePaths.isNotEmpty)
        .toList();
    if (withImages.isEmpty) return const <pw.Widget>[];

    final widgets = <pw.Widget>[
      pw.NewPage(),
      _buildSectionTitle('المرفقات', withImages.length),
    ];

    for (final txn in withImages) {
      final images = <_AppendixImage>[];
      for (final path in txn.imagePaths) {
        final image = await _loadAppendixImage(path);
        if (image != null) images.add(image);
      }
      if (images.isEmpty) {
        widgets.add(_atomic(_appendixHeadingOnly(txn)));
        continue;
      }

      // Bounded so heading + images + link always fit inside one page, no
      // matter how many photos the transaction has.
      final perImage = math.min(
        _maxPageImageHeight,
        _contentHeight * 0.7 / images.length,
      );
      widgets.add(_atomic(_appendixBlock(txn, images, perImage)));
    }

    return widgets;
  }

  pw.Widget _appendixHeadingOnly(ReportTransaction txn) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _appendixHeading(txn),
          pw.SizedBox(height: 8),
          pw.Text('الصورة غير متوفرة', style: _style(10, color: _muted)),
          pw.SizedBox(height: 8),
          pw.Link(
            destination: 'row_${txn.id}',
            child: pw.Text(
              'رجوع للمعاملة',
              style: _style(10, color: _primaryDark),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _appendixBlock(
    ReportTransaction txn,
    List<_AppendixImage> images,
    double perImage,
  ) {
    final innerWidth = _contentWidth - 26;

    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _appendixHeading(txn),
          pw.SizedBox(height: 8),
          for (final image in images) ...[
            _sizedImage(image, innerWidth, perImage),
            pw.SizedBox(height: 6),
          ],
          pw.SizedBox(height: 4),
          pw.Link(
            destination: 'row_${txn.id}',
            child: pw.Text(
              'رجوع للمعاملة',
              style: _style(10, color: _primaryDark),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _appendixHeading(ReportTransaction txn) {
    final note = txn.note?.trim() ?? '';
    final parts = <String>[
      _date.format(DateTime.parse(txn.date)),
      CurrencyFormatter.format(txn.amount),
      typeLabelAr(txn.state),
      if (note.isNotEmpty) note,
    ];
    return pw.Anchor(
      name: 'tx_${txn.id}',
      child: pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _border, width: 1)),
        ),
        child: pw.Text(parts.join(' · '), style: _style(11.5, bold: true)),
      ),
    );
  }

  pw.Widget _sizedImage(_AppendixImage image, double maxWidth, double maxHeight) {
    final scale = math.min(maxWidth / image.width, maxHeight / image.height);
    return pw.Image(
      image.provider,
      width: image.width * scale,
      height: image.height * scale,
      fit: pw.BoxFit.contain,
    );
  }

  /// Downscales to [_imageLongSide], bakes EXIF rotation and re-encodes so a
  /// photo cannot blow up the PDF. `null` means "file missing or unreadable".
  Future<_AppendixImage?> _loadAppendixImage(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final raw = await file.readAsBytes();
      if (raw.isEmpty) return null;

      final decoded = im.decodeImage(raw);
      if (decoded == null) return null;

      var source = im.bakeOrientation(decoded);
      if (source.width > _imageLongSide || source.height > _imageLongSide) {
        source = source.width >= source.height
            ? im.copyResize(source, width: _imageLongSide)
            : im.copyResize(source, height: _imageLongSide);
      }

      final bytes = im.encodeJpg(source, quality: _imageQuality);
      return _AppendixImage(
        pw.MemoryImage(Uint8List.fromList(bytes)),
        source.width,
        source.height,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- footer

  pw.Widget _buildFooter(pw.Context context) {
    // Called once during layout (only the height matters there) and again
    // while painting, after every page exists — hence the live page count.
    final pages = context.document.pdfPageList.pages;
    final index = pages.indexOf(context.page);
    final current = index < 0 ? 1 : index + 1;
    final total = pages.length;

    return pw.Container(
      width: double.infinity,
      height: _footerHeight,
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 0.5)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'صفحة $current من $total',
              style: _style(9, color: _muted),
              textAlign: pw.TextAlign.start,
            ),
          ),
          pw.Text(
            'دفتر الديون',
            style: _style(9, color: _muted),
            textAlign: pw.TextAlign.end,
          ),
        ],
      ),
    );
  }
}

class _AppendixImage {
  const _AppendixImage(this.provider, this.width, this.height);

  final pw.MemoryImage provider;
  final int width;
  final int height;
}
