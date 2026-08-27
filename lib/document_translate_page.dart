import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';

/// 文档翻译（PRO 工具）：选 TXT/MD/CSV/DOCX → 提取文本 → 分块翻译(MyMemory, 免费) → 结果可复制。
/// 独立成页，避免在 TranslatePage 与 ProToolsPage 之间互相依赖。
class DocumentTranslatePage extends StatefulWidget {
  const DocumentTranslatePage({super.key});
  @override
  State<DocumentTranslatePage> createState() => _DocumentTranslatePageState();
}

class _DocumentTranslatePageState extends State<DocumentTranslatePage> {
  final List<Map<String, String>> _langList = [
    {'name': '中文', 'code': 'zh-CN'},
    {'name': '英语', 'code': 'en'},
    {'name': '日语', 'code': 'ja'},
    {'name': '韩语', 'code': 'ko'},
    {'name': '法语', 'code': 'fr'},
    {'name': '德语', 'code': 'de'},
    {'name': '俄语', 'code': 'ru'},
    {'name': '西班牙语', 'code': 'es'},
    {'name': '意大利语', 'code': 'it'},
    {'name': '葡萄牙语', 'code': 'pt'},
    {'name': '阿拉伯语', 'code': 'ar'},
    {'name': '印地语', 'code': 'hi'},
    {'name': '土耳其语', 'code': 'tr'},
    {'name': '荷兰语', 'code': 'nl'},
  ];
  int _fromIndex = 0;
  int _toIndex = 1;

  Future<void> _pickAndTranslate() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'csv', 'docx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _snack('无法读取文件内容');
      return;
    }
    final name = file.name.toLowerCase();
    final text = name.endsWith('.docx')
        ? _extractDocxText(bytes)
        : utf8.decode(bytes, allowMalformed: true);
    if (text.trim().isEmpty) {
      _snack('未提取到文本（PDF 暂不支持，请先转成 TXT/DOCX）');
      return;
    }
    final from = _langList[_fromIndex]['code']!;
    final to = _langList[_toIndex]['code']!;
    final progress = ValueNotifier<String>('准备中…');
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('文档翻译'),
        content: ValueListenableBuilder<String>(
          valueListenable: progress,
          builder: (_, v, __) => Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 12),
            Expanded(child: Text(v)),
          ]),
        ),
      ),
    ));
    try {
      final out = await _translateDocument(text, from, to, (d, t) {
        progress.value = '翻译中 $d/$t';
      });
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
      _showResult(out);
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
      _snack('翻译失败：$e');
    }
  }

  Future<String> _translateDocument(String text, String from, String to,
      void Function(int done, int total) onProgress) async {
    final chunks = _chunkText(text);
    if (chunks.isEmpty) return '';
    final sb = StringBuffer();
    for (var i = 0; i < chunks.length; i++) {
      onProgress(i + 1, chunks.length);
      final t = await _translateViaMymemory(chunks[i], from, to);
      sb.write(t);
      sb.write('\n\n');
    }
    return sb.toString().trim();
  }

  Future<String> _translateViaMymemory(String text, String from, String to) async {
    if (text.trim().isEmpty) return '';
    final uri = Uri.https('api.mymemory.translated.net', '/get', {
      'q': text,
      'langpair': '$from|$to',
    });
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return text;
      final data = json.decode(utf8.decode(resp.bodyBytes));
      final rd = data is Map<String, dynamic> ? data['responseData'] : null;
      final t =
          rd is Map<String, dynamic> ? rd['translatedText'] as String? : null;
      if (t == null || t.isEmpty || t.startsWith('MYMEMORY WARNING')) return text;
      return t;
    } catch (_) {
      return text;
    }
  }

  List<String> _chunkText(String text) {
    final paras = text.split('\n');
    final chunks = <String>[];
    final buf = StringBuffer();
    for (final p in paras) {
      final piece = p.trim();
      if (piece.isEmpty) continue;
      if (buf.isNotEmpty && buf.length + piece.length > 400) {
        chunks.add(buf.toString().trim());
        buf.clear();
      }
      buf.write(piece);
      buf.write('\n');
    }
    if (buf.isNotEmpty) chunks.add(buf.toString().trim());
    return chunks;
  }

  String _extractDocxText(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? docFile;
      for (final f in archive.files) {
        if (f.name == 'word/document.xml') {
          docFile = f;
          break;
        }
      }
      if (docFile == null) return '';
      final xml = utf8.decode(docFile.content as List<int>);
      final withBreaks = xml.replaceAll(RegExp(r'</w:p>'), '\n');
      final matches =
          RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true).allMatches(withBreaks);
      final sb = StringBuffer();
      for (final m in matches) {
        sb.write(_xmlUnescape(m.group(1) ?? ''));
      }
      return sb.toString().trim();
    } catch (_) {
      return '';
    }
  }

  String _xmlUnescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ');

  void _showResult(String translated) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('文档翻译结果'),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: SingleChildScrollView(child: SelectableText(translated)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: translated));
              Navigator.pop(ctx);
              _snack('译文已复制');
            },
            child: const Text('复制译文'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文档翻译'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('支持 TXT / MD / CSV / DOCX，整篇分块翻译，结果可复制。',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _fromIndex,
                  decoration: const InputDecoration(labelText: '源语言'),
                  items: _langList
                      .asMap()
                      .entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value['name']!)))
                      .toList(),
                  onChanged: (v) => setState(() => _fromIndex = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _toIndex,
                  decoration: const InputDecoration(labelText: '目标语言'),
                  items: _langList
                      .asMap()
                      .entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value['name']!)))
                      .toList(),
                  onChanged: (v) => setState(() => _toIndex = v!),
                ),
              ),
            ]),
            const Spacer(),
            FilledButton.icon(
              onPressed: _pickAndTranslate,
              icon: const Icon(Icons.upload_file),
              label: const Text('选择文件并翻译'),
            ),
          ],
        ),
      ),
    );
  }
}
