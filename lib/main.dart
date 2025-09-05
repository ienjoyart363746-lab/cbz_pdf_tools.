import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:native_pdf_renderer/native_pdf_renderer.dart';
import 'package:reorderables/reorderables.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CbzPdfApp());
}

class CbzPdfApp extends StatelessWidget {
  const CbzPdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CBZ ↔ PDF Tools',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4F46E5),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4F46E5),
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _log = <String>[];
  bool _busy = false;

  void _append(String s) => setState(() => _log.add(s));

  Future<String> _defaultOutDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final out = Directory('${dir.path}/CBZ_PDF_Output');
    if (!out.existsSync()) out.createSync(recursive: true);
    return out.path;
  }

  // ================== CBZ → PDF ==================
  Future<void> _convertCbz() async {
    setState(() => _busy = true);
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['cbz', 'zip'],
        withData: true,
      );
      if (res == null) return;

      final outDir = await _defaultOutDir();
      for (final f in res.files) {
        _append('Converting ${f.name} ...');
        final bytes = f.bytes ?? await File(f.path!).readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);
        final images = archive.files.where((fe) =>
            !fe.isFile ? false : fe.name.toLowerCase().endsWith('.jpg') || fe.name.toLowerCase().endsWith('.png'))
          ..toList();
        images.sort((a, b) => a.name.compareTo(b.name));

        final pdf = pw.Document();
        for (final img in images) {
          final data = img.content as List<int>;
          final pwImage = pw.MemoryImage(Uint8List.fromList(data));
          pdf.addPage(pw.Page(build: (_) => pw.Center(child: pw.Image(pwImage))));
        }

        final outPath = '$outDir/${f.name.replaceAll(RegExp(r'\\.(cbz|zip)\$'), '')}.pdf';
        await File(outPath).writeAsBytes(await pdf.save());
        _append('✔ Saved: ${File(outPath).uri.pathSegments.last}');
      }
      _append('All conversions done.');
    } catch (e) {
      _append('Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  // ================== Quick Merge ==================
  Future<void> _mergeQuick() async {
    setState(() => _busy = true);
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (res == null || res.files.length < 2) return;

      final outDir = await _defaultOutDir();
      final files = res.paths.whereType<String>().map((p) => File(p)).toList();
      final outPath = '$outDir/merged_quick_${DateTime.now().millisecondsSinceEpoch}.pdf';

      await _mergeAsRaster(files, outPath);
      _append('✔ Quick merged: ${File(outPath).uri.pathSegments.last}');
    } catch (e) {
      _append('Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  // ================== Advanced Merge ==================
  Future<void> _mergeAdvanced() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (res == null || res.files.length < 2) return;
    final files = res.paths.whereType<String>().map((p) => File(p)).toList();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MergeReorderScreen(initialFiles: files)),
    );
  }

  // ================== Rename PDF ==================
  Future<void> _renamePdf() async {
    setState(() => _busy = true);
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (res == null) return;
      final src = File(res.files.single.path!);
      final dir = await _defaultOutDir();

      final ctl = TextEditingController(text: src.uri.pathSegments.last);
      final newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('New file name'),
          content: TextField(controller: ctl),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Save')),
          ],
        ),
      );
      if (newName == null || newName.isEmpty) return;

      final dest = '$dir/${newName.endsWith('.pdf') ? newName : '$newName.pdf'}';
      await File(src.path).copy(dest);
      _append('✔ Saved copy as: ${File(dest).uri.pathSegments.last}');
    } catch (e) {
      _append('Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('CBZ ↔ PDF Tools'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _log.isEmpty ? null : () => Share.share(_log.join('\\n')),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(title: 'CBZ → PDF', subtitle: 'Convert CBZ archives into PDFs.', icon: Icons.photo_library_outlined, color: cs.primaryContainer, onPressed: _busy ? null : _convertCbz),
          const SizedBox(height: 12),
          _Card(title: 'Merge PDFs (Quick)', subtitle: 'Merge instantly in current order.', icon: Icons.picture_as_pdf_outlined, color: cs.secondaryContainer, onPressed: _busy ? null : _mergeQuick),
          const SizedBox(height: 12),
          _Card(title: 'Merge PDFs (Advanced)', subtitle: 'Pick, reorder, sort, then merge.', icon: Icons.list_alt_outlined, color: cs.tertiaryContainer, onPressed: _busy ? null : _mergeAdvanced),
          const SizedBox(height: 12),
          _Card(title: 'Rename / Save Copy', subtitle: 'Pick a PDF and rename it.', icon: Icons.drive_file_rename_outline, color: cs.surfaceVariant, onPressed: _busy ? null : _renamePdf),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          _LogView(lines: _log),
        ],
      ),
    );
  }
}

// ================== Merge Helper (Raster Merge) ==================
Future<void> _mergeAsRaster(List<File> files, String outPath) async {
  final pdf = pw.Document();
  for (final f in files) {
    final doc = await PdfDocument.openFile(f.path);
    for (int i = 1; i <= doc.pagesCount; i++) {
      final page = await doc.getPage(i);
      final img = await page.render(width: page.width, height: page.height, format: PdfPageImageFormat.png);
      pdf.addPage(pw.Page(build: (_) => pw.Image(pw.MemoryImage(img.bytes))));
      await page.close();
    }
    await doc.close();
  }
  await File(outPath).writeAsBytes(await pdf.save());
}

// ================== Advanced Merge Screen ==================
class MergeReorderScreen extends StatefulWidget {
  final List<File> initialFiles;
  const MergeReorderScreen({super.key, required this.initialFiles});
  @override
  State<MergeReorderScreen> createState() => _MergeReorderScreenState();
}

class _MergeReorderScreenState extends State<MergeReorderScreen> {
  late List<File> files;
  final Map<String, ImageProvider?> _thumbCache = {};
  final _log = <String>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    files = [...widget.initialFiles]..sort((a, b) => a.path.compareTo(b.path));
    _generateThumbnails();
  }

  Future<void> _generateThumbnails() async {
    for (final f in files) {
      if (_thumbCache.containsKey(f.path)) continue;
      try {
        final doc = await PdfDocument.openFile(f.path);
        final page = await doc.getPage(1);
        final img = await page.render(width: 120, height: 160, format: PdfPageImageFormat.png);
        await page.close();
        _thumbCache[f.path] = MemoryImage(img.bytes);
      } catch (_) {
        _thumbCache[f.path] = null;
      }
      if (mounted) setState(() {});
    }
  }

  void _sortAZ() => setState(() => files.sort((a, b) => a.path.compareTo(b.path)));
  void _sortZA() => setState(() => files.sort((a, b) => b.path.compareTo(a.path)));
  void _sortDate() => setState(() => files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync())));

  Future<String> _defaultOutDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final out = Directory('${dir.path}/CBZ_PDF_Output');
    if (!out.existsSync()) out.createSync(recursive: true);
    return out.path;
  }

  Future<void> _merge() async {
    setState(() => _busy = true);
    try {
      final outDir = await _defaultOutDir();
      final outPath = '$outDir/merged_adv_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await _mergeAsRaster(files, outPath);
      setState(() => _log.add('✔ Saved merged file: $outPath'));
    } catch (e) {
      setState(() => _log.add('Error: $e'));
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Merge'),
        actions: [
          IconButton(onPressed: _sortAZ, icon: const Icon(Icons.sort_by_alpha)),
          IconButton(onPressed: _sortZA, icon: const Icon(Icons.sort)),
          IconButton(onPressed: _sortDate, icon: const Icon(Icons.calendar_today)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ReorderableColumn(
              crossAxisAlignment: CrossAxisAlignment.start,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  final f = files.removeAt(oldIndex);
                  files.insert(newIndex, f);
                });
              },
              children: [
                for (final f in files)
                  ListTile(
                    key: ValueKey(f.path),
                    leading: _thumbCache[f.path] != null
                        ? Image(image: _thumbCache[f.path]!, width: 60, height: 80, fit: BoxFit.cover)
                        : const SizedBox(width: 60, height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                    title: Text(f.uri.pathSegments.last),
                    subtitle: Text(f.path),
                  ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          ElevatedButton.icon(
            onPressed: _busy ? null : _merge,
            icon: const Icon(Icons.merge_type),
            label: const Text('Merge PDFs'),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _log.length,
              itemBuilder: (ctx, i) => ListTile(title: Text(_log[i])),
            ),
          ),
        ],
      ),
    );
  }
}

// ================== Small UI Helpers ==================
class _Card extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  const _Card({required this.title, required this.subtitle, required this.icon, required this.color, this.onPressed});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(icon, size: 36),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: IconButton(icon: const Icon(Icons.play_arrow), onPressed: onPressed),
      ),
    );
  }
}

class _LogView extends StatelessWidget {
  final List<String> lines;
  const _LogView({required this.lines});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
      height: 200,
      child: ListView(children: [for (final l in lines) Text(l)]),
    );
  }
}