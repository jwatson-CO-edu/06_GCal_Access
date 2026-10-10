import 'dart:io';

import 'package:path/path.dart' as p;

/// Names of `.md` files directly inside [dirPath], sorted; null if the
/// directory is missing or has no Markdown files.
List<String>? listMarkdownFiles(
  String dirPath, {
  void Function(Object)? onError,
}) {
  try {
    final dir = Directory(dirPath);
    if (dirPath.trim().isEmpty || !dir.existsSync()) return null;
    final names =
        dir
            .listSync(followLinks: false)
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .where((n) => n.toLowerCase().endsWith('.md'))
            .toList()
          ..sort();
    return names.isEmpty ? null : names;
  } on FileSystemException catch (e) {
    onError?.call(
      e,
    ); // e.g. permission denied; a missing directory is not an error
    return null;
  }
}

/// Lines containing `- [ ]`, trimmed. Throws if the file can't be read.
List<String> extractTasks(String path) =>
    File(path)
        .readAsLinesSync()
        .where((l) => l.contains('- [ ]'))
        .map((l) => l.trim())
        .toList();
