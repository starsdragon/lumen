import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/services/file_import_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Uint8List zipFiles(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  final service = FileImportService();

  test('imports text and markdown', () async {
    final result = await service.extract(
      name: 'notes.md',
      mime: 'text/markdown',
      bytes: Uint8List.fromList(utf8.encode('# 标题\n\n这是正文。')),
    );
    expect(result.text, contains('这是正文'));
    expect(result.truncated, isFalse);
  });

  test('imports docx and pptx text', () async {
    final docx = zipFiles({
      'word/document.xml':
          '<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>第一段</w:t></w:r></w:p><w:p><w:r><w:t>第二段</w:t></w:r></w:p></w:body></w:document>',
    });
    final docResult = await service.extract(
      name: 'report.docx',
      mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      bytes: docx,
    );
    expect(docResult.text, contains('第一段'));
    expect(docResult.text, contains('第二段'));

    final pptx = zipFiles({
      'ppt/slides/slide1.xml':
          '<?xml version="1.0"?><p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:p><a:r><a:t>幻灯片标题</a:t></a:r></a:p></p:sld>',
    });
    final pptResult = await service.extract(
      name: 'deck.pptx',
      mime: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      bytes: pptx,
    );
    expect(pptResult.text, contains('幻灯片标题'));
  });

  test('imports xlsx cells', () async {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    sheet.updateCell(CellIndex.indexByString('A1'), TextCellValue('姓名'));
    sheet.updateCell(CellIndex.indexByString('B1'), TextCellValue('部门'));
    final bytes = Uint8List.fromList(excel.encode()!);
    final result = await service.extract(
      name: 'table.xlsx',
      mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      bytes: bytes,
    );
    expect(result.text, contains('姓名'));
    expect(result.text, contains('部门'));
  });

  test('imports PDF text', () async {
    final document = PdfDocument();
    final page = document.pages.add();
    page.graphics.drawString(
      'Hello PDF',
      PdfStandardFont(PdfFontFamily.helvetica, 12),
      bounds: const Rect.fromLTWH(20, 20, 200, 30),
    );
    final bytes = Uint8List.fromList(document.saveSync());
    document.dispose();
    final result = await service.extract(
      name: 'sample.pdf',
      mime: 'application/pdf',
      bytes: bytes,
    );
    expect(result.text, contains('Hello PDF'));
  });

  test('rejects unsupported legacy office formats', () async {
    expect(
      () => service.extract(
        name: 'old.doc',
        mime: 'application/msword',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(isA<FileImportException>()),
    );
  });
}
