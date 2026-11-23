import 'dart:convert';

enum ProjectFileStatus { pending, generating, generated, failed }

class ProjectFileTask {
  final String path;
  final String purpose;
  final List<String> dependsOn;
  final ProjectFileStatus status;
  final String? error;
  final DateTime? updatedAt;

  const ProjectFileTask({
    required this.path,
    required this.purpose,
    this.dependsOn = const [],
    this.status = ProjectFileStatus.pending,
    this.error,
    this.updatedAt,
  });

  ProjectFileTask copyWith({
    ProjectFileStatus? status,
    String? error,
    bool clearError = false,
    DateTime? updatedAt,
  }) => ProjectFileTask(
    path: path,
    purpose: purpose,
    dependsOn: dependsOn,
    status: status ?? this.status,
    error: clearError ? null : (error ?? this.error),
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'path': path,
    'purpose': purpose,
    'dependsOn': dependsOn,
    'status': status.name,
    'error': error,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory ProjectFileTask.fromJson(Map<String, dynamic> json) => ProjectFileTask(
    path: json['path'] as String,
    purpose: json['purpose'] as String? ?? '',
    dependsOn: (json['dependsOn'] as List? ?? const []).cast<String>(),
    status: ProjectFileStatus.values.firstWhere(
      (v) => v.name == json['status'],
      orElse: () => ProjectFileStatus.pending,
    ),
    error: json['error'] as String?,
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
  );
}

class GeneratedFileRecord {
  final String path;
  final String purpose;
  final int characterCount;
  final DateTime generatedAt;

  const GeneratedFileRecord({
    required this.path,
    required this.purpose,
    required this.characterCount,
    required this.generatedAt,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'purpose': purpose,
    'characterCount': characterCount,
    'generatedAt': generatedAt.toIso8601String(),
  };

  factory GeneratedFileRecord.fromJson(Map<String, dynamic> json) => GeneratedFileRecord(
    path: json['path'] as String,
    purpose: json['purpose'] as String? ?? '',
    characterCount: json['characterCount'] as int? ?? 0,
    generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class ProjectMemory {
  final String id;
  final String name;
  final String description;
  final String techStack;
  final String databaseSchema;
  final List<String> technicalDecisions;
  final List<String> pendingTasks;
  final List<ProjectFileTask> fileTasks;
  final List<GeneratedFileRecord> generatedFiles;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int schemaVersion;

  const ProjectMemory({
    required this.id,
    required this.name,
    required this.description,
    this.techStack = '',
    this.databaseSchema = '',
    this.technicalDecisions = const [],
    this.pendingTasks = const [],
    this.fileTasks = const [],
    this.generatedFiles = const [],
    required this.createdAt,
    required this.updatedAt,
    this.schemaVersion = 1,
  });

  ProjectMemory copyWith({
    String? name,
    String? description,
    String? techStack,
    String? databaseSchema,
    List<String>? technicalDecisions,
    List<String>? pendingTasks,
    List<ProjectFileTask>? fileTasks,
    List<GeneratedFileRecord>? generatedFiles,
    DateTime? updatedAt,
  }) => ProjectMemory(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    techStack: techStack ?? this.techStack,
    databaseSchema: databaseSchema ?? this.databaseSchema,
    technicalDecisions: technicalDecisions ?? this.technicalDecisions,
    pendingTasks: pendingTasks ?? this.pendingTasks,
    fileTasks: fileTasks ?? this.fileTasks,
    generatedFiles: generatedFiles ?? this.generatedFiles,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
    schemaVersion: schemaVersion,
  );

  String toCompactContext({int maxItems = 20}) {
    final completed = fileTasks.where((t) => t.status == ProjectFileStatus.generated).length;
    final failed = fileTasks.where((t) => t.status == ProjectFileStatus.failed).length;
    final plan = fileTasks.take(maxItems).map((t) => '- ${t.path}: ${t.status.name} — ${t.purpose}').join('\n');
    return '''
PROJECT: $name
DESCRIPTION: $description
TECH STACK: ${techStack.isEmpty ? 'Not decided' : techStack}
DATABASE: ${databaseSchema.isEmpty ? 'Not designed' : databaseSchema}
DECISIONS:
${technicalDecisions.isEmpty ? '- None recorded' : technicalDecisions.map((e) => '- $e').join('\n')}
PENDING TASKS:
${pendingTasks.isEmpty ? '- None recorded' : pendingTasks.map((e) => '- $e').join('\n')}
FILES: $completed generated / ${fileTasks.length} planned; $failed failed
FILE PLAN:
${plan.isEmpty ? '- No files planned' : plan}
'''.trim();
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'name': name,
    'description': description,
    'techStack': techStack,
    'databaseSchema': databaseSchema,
    'technicalDecisions': technicalDecisions,
    'pendingTasks': pendingTasks,
    'fileTasks': fileTasks.map((e) => e.toJson()).toList(),
    'generatedFiles': generatedFiles.map((e) => e.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory ProjectMemory.fromJson(Map<String, dynamic> json) => ProjectMemory(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Untitled project',
    description: json['description'] as String? ?? '',
    techStack: json['techStack'] as String? ?? '',
    databaseSchema: json['databaseSchema'] as String? ?? '',
    technicalDecisions: (json['technicalDecisions'] as List? ?? const []).cast<String>(),
    pendingTasks: (json['pendingTasks'] as List? ?? const []).cast<String>(),
    fileTasks: (json['fileTasks'] as List? ?? const [])
      .map((e) => ProjectFileTask.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    generatedFiles: (json['generatedFiles'] as List? ?? const [])
      .map((e) => GeneratedFileRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    schemaVersion: json['schemaVersion'] as int? ?? 1,
  );
}
