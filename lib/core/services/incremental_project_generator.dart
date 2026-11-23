import 'dart:io';

import '../models/project_memory.dart';
import 'project_memory_service.dart';

class FileGenerationInput {
  final String projectName;
  final String projectDescription;
  final String projectContext;
  final String filePath;
  final String filePurpose;
  final List<String> dependencies;
  final Map<String, String> existingFiles;

  const FileGenerationInput({
    required this.projectName,
    required this.projectDescription,
    required this.projectContext,
    required this.filePath,
    required this.filePurpose,
    required this.dependencies,
    required this.existingFiles,
  });
}

typedef FileContentGenerator = Future<String> Function(FileGenerationInput input);

class GenerationProgress {
  final String projectId;
  final String currentFile;
  final int completed;
  final int total;
  final bool finished;
  final String? error;

  const GenerationProgress({
    required this.projectId,
    required this.currentFile,
    required this.completed,
    required this.total,
    required this.finished,
    this.error,
  });

  double get fraction => total == 0 ? 1 : completed / total;
}

class IncrementalProjectGenerator {
  final ProjectMemoryService memoryService;
  final FileContentGenerator generateFile;
  final int maxContextFiles;

  IncrementalProjectGenerator({
    required this.memoryService,
    required this.generateFile,
    this.maxContextFiles = 8,
  });

  static final RegExp _validSegment = RegExp(r'^[a-zA-Z0-9_.-]+$');

  String _validateRelativePath(String value) {
    final normalized = value.replaceAll('\\', '/').trim();
    if (normalized.isEmpty || normalized.startsWith('/') || normalized.contains(':')) {
      throw ArgumentError.value(value, 'path', 'Path must be relative to the project workspace');
    }
    final segments = normalized.split('/');
    if (segments.any((s) => s.isEmpty || s == '.' || s == '..' || !_validSegment.hasMatch(s))) {
      throw ArgumentError.value(value, 'path', 'Path contains an unsafe segment');
    }
    return segments.join('/');
  }

  Future<ProjectMemory> createProject({
    required String id,
    required String name,
    required String description,
    required List<ProjectFileTask> filePlan,
    String techStack = '',
    String databaseSchema = '',
  }) async {
    if (filePlan.isEmpty) throw ArgumentError('The file plan cannot be empty');
    final seen = <String>{};
    final normalizedPlan = <ProjectFileTask>[];
    for (final task in filePlan) {
      final path = _validateRelativePath(task.path);
      if (!seen.add(path)) throw ArgumentError('Duplicate file path in plan: $path');
      normalizedPlan.add(ProjectFileTask(
        path: path,
        purpose: task.purpose,
        dependsOn: task.dependsOn.map(_validateRelativePath).toList(),
      ));
    }
    for (final task in normalizedPlan) {
      for (final dependency in task.dependsOn) {
        if (!seen.contains(dependency)) {
          throw ArgumentError('Unknown dependency "$dependency" referenced by "${task.path}"');
        }
      }
    }
    final now = DateTime.now();
    final memory = ProjectMemory(
      id: id,
      name: name,
      description: description,
      techStack: techStack,
      databaseSchema: databaseSchema,
      fileTasks: normalizedPlan,
      pendingTasks: normalizedPlan.map((e) => 'Generate ${e.path}').toList(),
      createdAt: now,
      updatedAt: now,
    );
    await memoryService.projectWorkspace(id);
    await memoryService.save(memory);
    return memory;
  }

  Future<Map<String, String>> _readExistingContext(
    Directory workspace,
    ProjectMemory memory,
    String currentPath,
  ) async {
    final records = memory.generatedFiles
      .where((r) => r.path != currentPath)
      .toList()
      .reversed
      .take(maxContextFiles)
      .toList()
      .reversed;
    final result = <String, String>{};
    for (final record in records) {
      final safePath = _validateRelativePath(record.path);
      final file = File('${workspace.path}/$safePath');
      if (await file.exists()) {
        result[safePath] = await file.readAsString();
      }
    }
    return result;
  }

  Future<File> _writeAtomically(Directory workspace, String relativePath, String content) async {
    final safePath = _validateRelativePath(relativePath);
    final destination = File('${workspace.path}/$safePath');
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.nexvora-tmp');
    await temporary.writeAsString(content, flush: true);
    if (await destination.exists()) await destination.delete();
    return temporary.rename(destination.path);
  }

  Future<GenerationProgress> generateNext(
    String projectId, {
    void Function(GenerationProgress progress)? onProgress,
  }) async {
    var memory = await memoryService.load(projectId);
    if (memory == null) throw StateError('Project $projectId does not exist');
    final workspace = await memoryService.projectWorkspace(projectId);
    final tasks = [...memory.fileTasks];
    final completed = tasks.where((t) => t.status == ProjectFileStatus.generated).length;
    final nextIndex = tasks.indexWhere((t) => t.status == ProjectFileStatus.pending || t.status == ProjectFileStatus.failed);

    if (nextIndex < 0) {
      final done = GenerationProgress(projectId: projectId, currentFile: '', completed: completed,
        total: tasks.length, finished: true);
      onProgress?.call(done);
      return done;
    }

    final task = tasks[nextIndex];
    final missingDependencies = task.dependsOn.where((path) {
      return !tasks.any((t) => t.path == path && t.status == ProjectFileStatus.generated);
    }).toList();
    if (missingDependencies.isNotEmpty) {
      final error = 'Dependencies must be generated first: ${missingDependencies.join(', ')}';
      tasks[nextIndex] = task.copyWith(status: ProjectFileStatus.failed, error: error, updatedAt: DateTime.now());
      memory = memory.copyWith(fileTasks: tasks);
      await memoryService.save(memory);
      final failed = GenerationProgress(projectId: projectId, currentFile: task.path,
        completed: completed, total: tasks.length, finished: false, error: error);
      onProgress?.call(failed);
      return failed;
    }

    tasks[nextIndex] = task.copyWith(status: ProjectFileStatus.generating, clearError: true, updatedAt: DateTime.now());
    memory = memory.copyWith(fileTasks: tasks);
    await memoryService.save(memory);

    try {
      final existing = await _readExistingContext(workspace, memory, task.path);
      final content = await generateFile(FileGenerationInput(
        projectName: memory.name,
        projectDescription: memory.description,
        projectContext: memory.toCompactContext(),
        filePath: task.path,
        filePurpose: task.purpose,
        dependencies: task.dependsOn,
        existingFiles: existing,
      ));
      if (content.trim().isEmpty) throw StateError('The model returned an empty file');
      await _writeAtomically(workspace, task.path, content);

      final now = DateTime.now();
      final updatedTasks = [...memory.fileTasks];
      updatedTasks[nextIndex] = updatedTasks[nextIndex].copyWith(
        status: ProjectFileStatus.generated, clearError: true, updatedAt: now);
      final records = memory.generatedFiles.where((r) => r.path != task.path).toList()
        ..add(GeneratedFileRecord(path: task.path, purpose: task.purpose,
          characterCount: content.length, generatedAt: now));
      final pending = updatedTasks
        .where((t) => t.status != ProjectFileStatus.generated)
        .map((t) => 'Generate ${t.path}')
        .toList();
      memory = memory.copyWith(fileTasks: updatedTasks, generatedFiles: records,
        pendingTasks: pending, updatedAt: now);
      await memoryService.save(memory);

      final count = updatedTasks.where((t) => t.status == ProjectFileStatus.generated).length;
      final progress = GenerationProgress(projectId: projectId, currentFile: task.path,
        completed: count, total: updatedTasks.length, finished: count == updatedTasks.length);
      onProgress?.call(progress);
      return progress;
    } catch (error) {
      final updatedTasks = [...memory!.fileTasks];
      updatedTasks[nextIndex] = updatedTasks[nextIndex].copyWith(
        status: ProjectFileStatus.failed, error: error.toString(), updatedAt: DateTime.now());
      memory = memory.copyWith(fileTasks: updatedTasks);
      await memoryService.save(memory);
      final progress = GenerationProgress(projectId: projectId, currentFile: task.path,
        completed: completed, total: updatedTasks.length, finished: false, error: error.toString());
      onProgress?.call(progress);
      return progress;
    }
  }

  Future<List<GenerationProgress>> generateAll(
    String projectId, {
    void Function(GenerationProgress progress)? onProgress,
    int maxAttemptsPerFile = 2,
  }) async {
    if (maxAttemptsPerFile < 1) throw ArgumentError.value(maxAttemptsPerFile, 'maxAttemptsPerFile');
    final results = <GenerationProgress>[];
    var attempts = 0;
    while (true) {
      final memory = await memoryService.load(projectId);
      if (memory == null) throw StateError('Project $projectId does not exist');
      final unfinished = memory.fileTasks.where(
        (t) => t.status == ProjectFileStatus.pending || t.status == ProjectFileStatus.failed);
      if (unfinished.isEmpty) break;
      final progress = await generateNext(projectId, onProgress: onProgress);
      results.add(progress);
      if (progress.error != null) {
        attempts++;
        if (attempts >= maxAttemptsPerFile) break;
      } else {
        attempts = 0;
      }
      if (progress.finished) break;
    }
    return results;
  }

  Future<String> readProjectFile(String projectId, String relativePath) async {
    final safePath = _validateRelativePath(relativePath);
    final workspace = await memoryService.projectWorkspace(projectId);
    final file = File('${workspace.path}/$safePath');
    if (!await file.exists()) throw FileSystemException('Project file not found', file.path);
    return file.readAsString();
  }
}
