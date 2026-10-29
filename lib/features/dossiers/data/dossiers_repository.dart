import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/models/dossier_category.dart';
import '../../../core/models/stored_statuses.dart';
import '../../../core/utils/today_provider.dart';
import '../../requirements/data/requirements_repository.dart';
import '../domain/dossier_models.dart';

/// Informations saisies dans le formulaire d'un dossier.
class DossierInput {
  const DossierInput({
    required this.title,
    this.category,
    this.description,
    this.deadline,
    this.notes,
  });

  final String title;
  final DossierCategory? category;
  final String? description;
  final DateTime? deadline;
  final String? notes;
}

class TaskInput {
  const TaskInput({required this.title, this.dueDate, this.notes});

  final String title;
  final DateTime? dueDate;
  final String? notes;
}

class DossiersRepository {
  DossiersRepository(this._db);

  final AppDatabase _db;

  Stream<List<DossierRow>> watchDossiers() =>
      _db.select(_db.dossiers).watch();

  Future<DossierRow?> getDossier(String id) => (_db.select(
    _db.dossiers,
  )..where((d) => d.id.equals(id))).getSingleOrNull();

  Stream<List<TaskRow>> watchAllTasks() => (_db.select(
    _db.tasks,
  )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).watch();

  Future<String> createDossier(DossierInput input) async {
    final now = DateTime.now();
    final id = newId();
    await _db
        .into(_db.dossiers)
        .insert(
          DossiersCompanion.insert(
            id: id,
            title: input.title.trim(),
            category: Value(input.category),
            description: Value(cleanText(input.description)),
            deadline: Value(input.deadline),
            notes: Value(cleanText(input.notes)),
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: Value(now),
          ),
        );
    return id;
  }

  Future<void> updateDossier(String id, DossierInput input) async {
    await (_db.update(_db.dossiers)..where((d) => d.id.equals(id))).write(
      DossiersCompanion(
        title: Value(input.title.trim()),
        category: Value(input.category),
        description: Value(cleanText(input.description)),
        deadline: Value(input.deadline),
        notes: Value(cleanText(input.notes)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setCompleted(String id, bool completed) async {
    await (_db.update(_db.dossiers)..where((d) => d.id.equals(id))).write(
      DossiersCompanion(
        status: Value(
          completed
              ? ManualDossierStatus.completed
              : ManualDossierStatus.inProgress,
        ),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setArchived(String id, bool archived) async {
    final now = DateTime.now();
    await (_db.update(_db.dossiers)..where((d) => d.id.equals(id))).write(
      DossiersCompanion(
        archivedAt: Value(archived ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> markOpened(String id) async {
    await (_db.update(_db.dossiers)..where((d) => d.id.equals(id))).write(
      DossiersCompanion(lastOpenedAt: Value(DateTime.now())),
    );
  }

  /// Supprime un dossier avec ses pièces, associations et tâches. Les
  /// documents de la bibliothèque sont conservés.
  Future<void> deleteDossier(String id) async {
    await _db.transaction(() async {
      final itemIds = _db.selectOnly(_db.requiredItems)
        ..addColumns([_db.requiredItems.id])
        ..where(_db.requiredItems.dossierId.equals(id));
      await (_db.delete(
        _db.itemDocumentLinks,
      )..where((l) => l.requiredItemId.isInQuery(itemIds))).go();
      await (_db.delete(
        _db.requiredItems,
      )..where((i) => i.dossierId.equals(id))).go();
      await (_db.delete(_db.tasks)..where((t) => t.dossierId.equals(id))).go();
      await (_db.delete(_db.dossiers)..where((d) => d.id.equals(id))).go();
    });
  }

  // ---------------------------------------------------------------------------
  // Tâches

  Future<void> createTask(String dossierId, TaskInput input) async {
    final now = DateTime.now();
    await _db
        .into(_db.tasks)
        .insert(
          TasksCompanion.insert(
            id: newId(),
            dossierId: dossierId,
            title: input.title.trim(),
            dueDate: Value(input.dueDate),
            notes: Value(cleanText(input.notes)),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> updateTask(String taskId, TaskInput input) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        title: Value(input.title.trim()),
        dueDate: Value(input.dueDate),
        notes: Value(cleanText(input.notes)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setTaskCompleted(String taskId, bool completed) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        isCompleted: Value(completed),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteTask(String taskId) async {
    await (_db.delete(_db.tasks)..where((t) => t.id.equals(taskId))).go();
  }
}

final dossiersRepositoryProvider = Provider<DossiersRepository>(
  (ref) => DossiersRepository(ref.watch(databaseProvider)),
);

final _dossierRowsProvider = StreamProvider<List<DossierRow>>(
  (ref) => ref.watch(dossiersRepositoryProvider).watchDossiers(),
);

final _allTasksProvider = StreamProvider<List<TaskRow>>(
  (ref) => ref.watch(dossiersRepositoryProvider).watchAllTasks(),
);

/// Tous les dossiers (archivés compris) avec leurs pièces évaluées. La
/// progression est recalculée à chaque modification de la base.
final dossierOverviewsProvider = Provider<AsyncValue<List<DossierOverview>>>((
  ref,
) {
  final dossiers = ref.watch(_dossierRowsProvider);
  final requirements = ref.watch(allRequirementsProvider);
  final tasks = ref.watch(_allTasksProvider);
  final today = ref.watch(todayProvider);

  if (dossiers.hasError) {
    return AsyncValue.error(dossiers.error!, dossiers.stackTrace!);
  }
  if (requirements.hasError) {
    return AsyncValue.error(requirements.error!, requirements.stackTrace!);
  }
  if (tasks.hasError) return AsyncValue.error(tasks.error!, tasks.stackTrace!);
  if (!dossiers.hasValue || !requirements.hasValue || !tasks.hasValue) {
    return const AsyncValue.loading();
  }

  final itemsByDossier = groupBy(requirements.requireValue, (r) => r.dossierId);
  final tasksByDossier = groupBy(tasks.requireValue, (t) => t.dossierId);
  return AsyncValue.data([
    for (final d in dossiers.requireValue)
      DossierOverview.build(
        dossier: d,
        requirements: itemsByDossier[d.id] ?? const [],
        tasks: tasksByDossier[d.id] ?? const [],
        today: today,
      ),
  ]);
});

/// Un dossier précis, ou `null` s'il n'existe plus.
final dossierOverviewProvider = Provider.autoDispose
    .family<AsyncValue<DossierOverview?>, String>((ref, id) {
      return ref
          .watch(dossierOverviewsProvider)
          .whenData((all) => all.firstWhereOrNull((d) => d.id == id));
    });
