import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'add_task_dialog.dart';
import 'services/auth_service.dart';
import 'services/calendar_service.dart';
import 'services/markdown_service.dart';
import 'services/status_log.dart';

const defaultDir = '/media/james/FILEPILE/Management/Notes/Daily Notes/';
const monoStyle = TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.3);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final log = StatusLog();
  // Route uncaught Dart errors to the status panel (and still to the console).
  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    log.error(details.exception, details.stack, 'Flutter error');
    presentError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.error(error, stack, 'Uncaught error');
    return true;
  };
  runApp(GCalApp(log: log));
}

class GCalApp extends StatelessWidget {
  GCalApp({super.key, StatusLog? log}) : log = log ?? StatusLog();

  final StatusLog log;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'GCal Access',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: HomePage(log: log),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.log});

  final StatusLog log;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _addressCtl = TextEditingController(text: defaultDir);
  final _taskCtl = TextEditingController();
  final _fileScroll = ScrollController();
  final _auth = AuthService();
  late final _calendar = CalendarService(_auth);

  StatusLog get _log => widget.log;

  List<String>? _files;
  String? _selectedFile;

  @override
  void initState() {
    super.initState();
    _refreshFiles();
  }

  @override
  void dispose() {
    _addressCtl.dispose();
    _taskCtl.dispose();
    _fileScroll.dispose();
    super.dispose();
  }

  void _refreshFiles() {
    setState(() {
      _files = listMarkdownFiles(
        _addressCtl.text,
        onError: (e) => _log.error(e, null, 'Listing folder'),
      );
      _selectedFile = null;
      _taskCtl.text = '';
    });
  }

  Future<void> _openFolder() async {
    final initial = Directory(_addressCtl.text).existsSync()
        ? _addressCtl.text
        : null;
    final String? path;
    try {
      path = await getDirectoryPath(initialDirectory: initial);
    } catch (e, st) {
      _log.error(e, st, 'Folder dialog');
      return;
    }
    if (path == null) return;
    _addressCtl.text = path.endsWith('/') ? path : '$path/';
    _refreshFiles();
  }

  void _selectFile(String name) {
    final dir = _addressCtl.text;
    final full = dir.endsWith('/') ? '$dir$name' : '$dir/$name';
    List<String> tasks;
    try {
      tasks = extractTasks(full);
    } catch (e, st) {
      _log.error(e, st, 'Reading $name');
      tasks = [];
    }
    setState(() {
      _selectedFile = name;
      _taskCtl.text = tasks.join('\n');
    });
  }

  Future<void> _onTaskTap() async {
    final text = _taskCtl.text;
    final sel = _taskCtl.selection;
    if (text.isEmpty || !sel.isValid) return;
    final offset = sel.baseOffset.clamp(0, text.length);
    final start = offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;
    var end = text.indexOf('\n', offset);
    if (end < 0) end = text.length;
    final line = text.substring(start, end);
    if (line.trim().isEmpty) return;
    _taskCtl.selection = TextSelection(baseOffset: start, extentOffset: end);

    final title = line.replaceFirst(RegExp(r'^[-*+]\s*\[ \]\s*'), '').trim();
    await showDialog<void>(
      context: context,
      builder: (_) => AddTaskAppointmentDialog(
        calendar: _calendar,
        log: _log,
        initialTitle: title.isEmpty ? line : title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final charW = _charWidth(context);
    final lineH = (monoStyle.fontSize! * monoStyle.height!);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: charW * 80 + 24,
                  child: TextField(
                    controller: _addressCtl,
                    style: monoStyle,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'Directory',
                    ),
                    onChanged: (_) => _refreshFiles(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _openFolder, child: const Text('Open')),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [_fileList(charW, lineH)],
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _taskBox()),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _StatusPanel(log: _log, lineHeight: lineH),
          ],
        ),
      ),
    );
  }

  Widget _fileList(double charW, double lineH) {
    final files = _files;
    final border = Border.all(color: Theme.of(context).colorScheme.outline);
    return Container(
      width: charW * 15 + 12 + 14, // 15 chars + padding + scrollbar
      height: lineH * 10 + 8,
      decoration: BoxDecoration(border: border),
      child: files == null
          ? const Padding(
              padding: EdgeInsets.all(4),
              child: Text('NO MARKDOWN HERE', style: monoStyle),
            )
          : Scrollbar(
              controller: _fileScroll,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _fileScroll,
                itemCount: files.length,
                itemExtent: lineH,
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                itemBuilder: (_, i) {
                  final name = files[i];
                  final selected = name == _selectedFile;
                  return Tooltip(
                    message: name,
                    waitDuration: const Duration(milliseconds: 500),
                    child: InkWell(
                      onTap: () => _selectFile(name),
                      child: Container(
                        color: selected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          name,
                          style: monoStyle,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _taskBox() => TextField(
    controller: _taskCtl,
    readOnly: true,
    expands: true,
    maxLines: null,
    minLines: null,
    textAlignVertical: TextAlignVertical.top,
    style: monoStyle,
    mouseCursor: SystemMouseCursors.click,
    onTap: _onTaskTap,
    decoration: InputDecoration(
      border: const OutlineInputBorder(),
      hintText: _selectedFile == null
          ? 'Select a Markdown file to load its tasks'
          : 'No tasks (lines containing "- [ ]") in $_selectedFile',
    ),
  );

  double _charWidth(BuildContext context) {
    final tp = TextPainter(
      text: TextSpan(text: 'M' * 100, style: monoStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return tp.width / 100;
  }
}

/// Scrolling log of errors (Dart exceptions and Google error codes) and notices.
class _StatusPanel extends StatefulWidget {
  const _StatusPanel({required this.log, required this.lineHeight});
  final StatusLog log;
  final double lineHeight;

  @override
  State<_StatusPanel> createState() => _StatusPanelState();
}

class _StatusPanelState extends State<_StatusPanel> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.log.addListener(_scrollToEnd);
  }

  @override
  void dispose() {
    widget.log.removeListener(_scrollToEnd);
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Status', style: Theme.of(context).textTheme.labelLarge),
            const Spacer(),
            TextButton(onPressed: widget.log.clear, child: const Text('Clear')),
          ],
        ),
        Container(
          height: widget.lineHeight * 6 + 8,
          width: double.infinity,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(border: Border.all(color: scheme.outline)),
          child: ListenableBuilder(
            listenable: widget.log,
            builder: (_, _) {
              final entries = widget.log.entries;
              if (entries.isEmpty) {
                return Text(
                  'Ready.',
                  style: monoStyle.copyWith(color: scheme.outline),
                );
              }
              return Scrollbar(
                controller: _scroll,
                child: SelectionArea(
                  child: ListView(
                    controller: _scroll,
                    children: [
                      for (final e in entries)
                        Text(
                          '${e.stamp}  ${e.level == StatusLevel.error ? 'ERROR' : 'INFO '}  ${e.text}',
                          style: monoStyle.copyWith(
                            color: e.level == StatusLevel.error
                                ? scheme.error
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
