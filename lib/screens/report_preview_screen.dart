import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../services/pdf_report_service.dart';

/// In-app page-by-page preview of a generated report.
///
/// The pages are raster images, which is why the hint below tells the user
/// that the appendix links only come alive in a real PDF reader.
class ReportPreviewScreen extends StatelessWidget {
  const ReportPreviewScreen({super.key, required this.report});

  final ReportPdf report;

  static const String linkHint =
      'الروابط بتشتغل عند فتح الملف في قارئ PDF خارجي';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('معاينة التقرير')),
      body: Column(
        children: [
          Expanded(
            child: PdfPreview(
              build: (_) async => report.bytes,
              pdfFileName: report.fileName,
              canChangeOrientation: false,
              canChangePageFormat: false,
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 9, 16, 12),
              color: AppColors.lightGrayBg,
              child: Text(
                linkHint,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
