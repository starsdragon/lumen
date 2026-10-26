import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

class FileImportResult {
  const FileImportResult({
    required this.name,
    required this.mime,
    required this.text,
    required this.sizeBytes,
    this.truncated = false,
    this.warning = '',
  });

  final String name;
  final String mime;
  final String text;
  final int sizeBytes;
  final bool truncated;
  final String warning;
}

class FileImportException implements Exception {
  const FileImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FileImportService {
  static const maxBytes = 20 * 1024 * 1024;
  static const maxChars = 20000;

  Future<FileImportResult> extract({
    required String name,
    required String mime,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      throw const FileImportException('文件是空的。');
    }
    if (bytes.length > maxBytes) {
      throw const FileImportException('文件超过 20MB，请压缩或截取后再导入。');
    }
    final lower = name.toLowerCase();
    final extension = lower.contains('.') ? lower.split('.').last : '';
    String text;
    String warning = '';
    try {
      if (_isTextExtension(extension) || mime.startsWith('text/')) {
        text = _decodeText(bytes);
        if (_isHtml(extension, mime)) {
          text = _htmlToText(text);
        }
      } else if (extension == 'pdf' || mime == 'application/pdf') {
        final result = await _pdf(bytes, name);
        text = result.$1;
        warning = result.$2;
      } else if (extension == 'docx') {
        text = _officeText(bytes, 'word/document.xml');
      } else if (extension == 'pptx') {
        text = _pptxText(bytes);
      } else if (extension == 'xlsx') {
        text = _xlsxText(bytes);
      } else if (['doc', 'xls', 'ppt'].contains(extension)) {
        throw const FileImportException('暂不支持旧版 Office 格式，请另存为 .docx / .xlsx / .pptx 后再导入。');
      } else {
        throw const FileImportException(
          '暂不支持这种文件类型。支持：PDF、DOCX、XLSX、PPTX、TXT、Markdown、JSON、CSV、HTML 和常见代码文件。',
        );
      }
    } on FileImportException {
      rethrow;
    } on Object catch (error) {
      throw FileImportException('解析文件失败：$error');
    }
    text = text.replaceAll('\u0000', '').trim();
    if (text.isEmpty) {
      throw FileImportException(
        extension == 'pdf'
            ? '没有从 PDF 中提取到文本，可能是扫描版 PDF（暂不支持 OCR）。'
            : '没有从文件中提取到可读文本。',
      );
    }
    final truncated = text.length > maxChars;
    if (truncated) {
      text = '${text.substring(0, maxChars)}\n\n（文件较长，以上为前 ${(maxChars / 1000).round()} 千字）';
      warning = warning.isEmpty ? '文件较长，已截取前 2 万字' : '$warning；已截取前 2 万字';
    }
    return FileImportResult(
      name: name,
      mime: mime.isEmpty ? _mimeForExtension(extension) : mime,
      text: text,
      sizeBytes: bytes.length,
      truncated: truncated,
      warning: warning,
    );
  }

  bool _isTextExtension(String extension) => const {
        'txt', 'md', 'markdown', 'json', 'jsonl', 'csv', 'tsv', 'xml', 'yaml', 'yml',
        'html', 'htm', 'css', 'scss', 'less', 'js', 'mjs', 'ts', 'tsx', 'jsx', 'dart',
        'py', 'java', 'kt', 'kts', 'c', 'h', 'cpp', 'hpp', 'cs', 'go', 'rs', 'rb', 'php',
        'sh', 'bash', 'zsh', 'ps1', 'sql', 'toml', 'ini', 'conf', 'log', 'tex', 'r', 'm',
      }.contains(extension);

  bool _isHtml(String extension, String mime) =>
      extension == 'html' || extension == 'htm' || mime.contains('html');

  String _decodeText(Uint8List bytes) {
    final decoded = utf8.decode(bytes, allowMalformed: true);
    if (!decoded.contains('\uFFFD')) return decoded;
    return latin1.decode(bytes);
  }

  String _htmlToText(String html) {
    final document = html_parser.parse(html);
    for (final tag in ['script', 'style', 'noscript', 'svg']) {
      for (final element in document.querySelectorAll(tag)) {
        element.remove();
      }
    }
    return document.body?.text ?? document.documentElement?.text ?? '';
  }

  Future<(String, String)> _pdf(Uint8List bytes, String name) async {
    final document = PdfDocument(inputBytes: bytes);
    try {
      final pageCount = document.pages.count;
      final endPage = pageCount > 60 ? 59 : pageCount - 1;
      final text = PdfTextExtractor(document)
          .extractText(startPageIndex: 0, endPageIndex: endPage)
          .trim();
      String warning = '';
      if (pageCount > 60) warning = 'PDF 页数较多，只读取了前 60 页';
      if (text.isEmpty) warning = 'PDF 未包含可提取文本，可能是扫描件';
      return (text, warning);
    } finally {
      document.dispose();
    }
  }

  String _officeText(Uint8List bytes, String target) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.files.where((entry) => entry.name == target).firstOrNull;
    if (file == null) throw const FileImportException('文件结构不完整，找不到正文内容。');
    final content = file.content;
    if (content is! List<int> || content.length > 30 * 1024 * 1024) {
      throw const FileImportException('文件内部内容过大。');
    }
    return _paragraphText(utf8.decode(content, allowMalformed: true));
  }

  String _pptxText(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final slides = archive.files
        .where((entry) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(entry.name))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final buffer = StringBuffer();
    for (final slide in slides.take(80)) {
      final content = slide.content;
      if (content is! List<int>) continue;
      final text = _paragraphText(utf8.decode(content, allowMalformed: true));
      if (text.trim().isEmpty) continue;
      buffer.writeln('【${slide.name.split('/').last.replaceAll('.xml', '')}】');
      buffer.writeln(text.trim());
      buffer.writeln();
      if (buffer.length >= maxChars) break;
    }
    return buffer.toString().trim();
  }

  String _xlsxText(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    final buffer = StringBuffer();
    for (final entry in workbook.tables.entries) {
      buffer.writeln('【工作表：${entry.key}】');
      final rows = entry.value.rows;
      for (final row in rows.take(300)) {
        final values = row
            .take(80)
            .map((cell) => cell?.value?.toString() ?? '')
            .map((value) => value.replaceAll(RegExp(r'\s+'), ' ').trim())
            .toList();
        while (values.isNotEmpty && values.last.isEmpty) {
          values.removeLast();
        }
        if (values.isNotEmpty) buffer.writeln(values.join(' | '));
        if (buffer.length >= maxChars) break;
      }
      buffer.writeln();
      if (buffer.length >= maxChars) break;
    }
    return buffer.toString().trim();
  }

  String _paragraphText(String xml) {
    final document = XmlDocument.parse(xml);
    final buffer = StringBuffer();
    for (final paragraph in document.descendants.whereType<XmlElement>()) {
      if (paragraph.name.local != 'p') continue;
      final text = paragraph.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 't')
          .map((element) => element.innerText)
          .join();
      if (text.trim().isNotEmpty) buffer.writeln(text.trim());
      if (buffer.length >= maxChars) break;
    }
    return buffer.toString().trim();
  }

  String _mimeForExtension(String extension) => switch (extension) {
        'pdf' => 'application/pdf',
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'md' || 'markdown' => 'text/markdown',
        'json' => 'application/json',
        'csv' => 'text/csv',
        'html' || 'htm' => 'text/html',
        _ => 'text/plain',
      };
}

String formatFileSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
