# NEXVORA AI — Phase 1 Architecture

## Workspace layout

```text
lib/
  core/
    models/
      project_memory.dart
    services/
      project_memory_service.dart
      incremental_project_generator.dart
  features/
    projects/
      screens/
      widgets/
      controllers/
    agent/
      contracts/
      orchestration/
  main.dart

docs/
  PHASE_1_ARCHITECTURE.md
```

## Phase 1 implementation

- `ProjectMemory` is the versioned, serializable project record. It stores the project brief, stack, database notes, decisions, pending work, file plan, and generated-file ledger.
- `ProjectMemoryService` persists one JSON memory file per project under the application documents directory and creates a separate project workspace directory.
- `IncrementalProjectGenerator` processes one planned file at a time, saves a checkpoint before generation, writes each file atomically, and records success/failure so generation can resume after an app restart.
- File paths are validated as relative paths. Absolute paths, drive prefixes, empty segments, and parent traversal are rejected.
- The generator accepts an injected `FileContentGenerator` callback. Phase 2 will connect that contract to the model router and skill prompts; Phase 1 deliberately does not contain a fake model implementation.

## Generator lifecycle

1. Create a project with an ordered file plan and dependency list.
2. The generator loads persistent project memory.
3. It selects the next pending or failed file whose dependencies are already generated.
4. It checkpoints the file as `generating`.
5. It passes the project summary and a bounded set of existing files to the injected generator.
6. It writes the returned content through a temporary file and atomic rename.
7. It records the generated file and updates pending tasks.
8. If generation fails, the error is persisted and the next run can resume.

## Storage boundary

Project memory and generated files are local to the app's private documents directory. This is not cloud synchronization. API provider integration, AST indexing, documentation retrieval, verification, tool execution, and component templates are scheduled for later phases.
