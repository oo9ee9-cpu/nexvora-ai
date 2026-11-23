import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/project_memory.dart';

class ProjectMemoryService {
  static const String _directoryName = 'nexvora_projects';
  static final RegExp _safeId = RegExp(r'^[a-zA-Z0-9_-]{1,80}$');

  Future<Directory> _rootDirectory() async {
    final appDirectory = await getApplicationDocumentsDirectory();
    final directory = Directory('${appDirectory.path}/$_directoryName');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _memoryFile(String projectId) async {
    if (!_safeId.hasMatch(projectId)) {
      throw ArgumentError.value(projectId, 'projectId', 'Invalid project identifier');
    }
    final root = await _rootDirectory();
    return File('${root.path}/$projectId.memory.json');
  }

  Future<Directory> projectWorkspace(String projectId) async {
    if (!_safeId.hasMatch(projectId)) {
      throw ArgumentError.value(projectId, 'projectId', 'Invalid project identifier');
    }
    final root = await _rootDirectory();
    final directory = Directory('${root.path}/$projectId');
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> save(ProjectMemory memory) async {
    final file = await _memoryFile(memory.id);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(memory.encode(), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
  }

  Future<ProjectMemory?> load(String projectId) async {
    final file = await _memoryFile(projectId);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Project memory must be a JSON object');
      }
      return ProjectMemory.fromJson(decoded);
    } on FormatException {
      final backup = File('${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      await file.rename(backup.path);
      rethrow;
    }
  }

  Future<List<ProjectMemory>> listProjects() async {
    final root = await _rootDirectory();
    final projects = <ProjectMemory>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.memory.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString());
        if (json is Map<String, dynamic>) {
          projects.add(ProjectMemory.fromJson(json));
        }
      } catch (_) {
        // A damaged project record does not prevent listing other projects.
      }
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  Future<void> deleteProject(String projectId) async {
    final memory = await _memoryFile(projectId);
    if (await memory.exists()) await memory.delete();
    final workspace = await projectWorkspace(projectId);
    if (await workspace.exists()) await workspace.delete(recursive: true);
  }

  Future<ProjectMemory> update(
    String projectId,
    ProjectMemory Function(ProjectMemory current) transform,
  ) async {
    final current = await load(projectId);
    if (current == null) throw StateError('Project $projectId was not found');
    final updated = transform(current);
    await save(updated);
    return updated;
  }
}
