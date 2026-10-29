import 'package:dossia/core/models/stored_statuses.dart';
import 'package:dossia/features/dossiers/domain/dossier_progress.dart';
import 'package:dossia/features/requirements/domain/item_status.dart';
import 'package:flutter_test/flutter_test.dart';

ItemEvaluation _item(ItemStatus status, {bool mandatory = true}) =>
    ItemEvaluation(
      status: status,
      isMandatory: mandatory,
      assignedQuantity: 0,
      requiredQuantity: 1,
    );

void main() {
  group('Progression', () {
    test('calculée uniquement sur les pièces obligatoires', () {
      final p = DossierProgress.fromEvaluations([
        _item(ItemStatus.available),
        _item(ItemStatus.missing),
        _item(ItemStatus.toVerify),
        _item(ItemStatus.available),
        _item(ItemStatus.optional, mandatory: false),
        _item(ItemStatus.available, mandatory: false),
      ]);
      expect(p.mandatoryTotal, 4);
      expect(p.mandatoryAvailable, 2);
      expect(p.mandatoryMissing, 1);
      expect(p.mandatoryToVerify, 1);
      expect(p.optionalTotal, 2);
      expect(p.optionalAvailable, 1);
      expect(p.percent, 50);
      expect(p.label, '50 %');
    });

    test('une pièce facultative manquante ne diminue pas la progression', () {
      final without = DossierProgress.fromEvaluations([
        _item(ItemStatus.available),
      ]);
      final withOptional = DossierProgress.fromEvaluations([
        _item(ItemStatus.available),
        _item(ItemStatus.optional, mandatory: false),
      ]);
      expect(without.percent, 100);
      expect(withOptional.percent, 100);
    });

    test('les pièces à vérifier ou à renouveler ne comptent pas comme '
        'disponibles', () {
      final p = DossierProgress.fromEvaluations([
        _item(ItemStatus.toVerify),
        _item(ItemStatus.toRenew),
      ]);
      expect(p.percent, 0);
      expect(p.mandatoryToVerify, 1);
      expect(p.mandatoryToRenew, 1);
      expect(p.mandatoryPending, 2);
    });

    test('sans pièce obligatoire : « Aucune pièce obligatoire », pas 100 %',
        () {
      final empty = DossierProgress.fromEvaluations(const []);
      final onlyOptional = DossierProgress.fromEvaluations([
        _item(ItemStatus.available, mandatory: false),
      ]);
      for (final p in [empty, onlyOptional]) {
        expect(p.hasMandatoryItems, isFalse);
        expect(p.percent, isNull);
        expect(p.ratio, isNull);
        expect(p.label, 'Aucune pièce obligatoire');
      }
    });

    test('arrondi à l’inférieur : 100 % seulement si tout est disponible', () {
      final p = DossierProgress.fromEvaluations([
        for (var i = 0; i < 199; i++) _item(ItemStatus.available),
        _item(ItemStatus.missing),
      ]);
      expect(p.percent, 99);
      expect(p.allMandatoryAvailable, isFalse);
    });
  });

  group('Statut du dossier', () {
    DossierStatus status({
      bool archived = false,
      ManualDossierStatus manual = ManualDossierStatus.inProgress,
      required List<ItemEvaluation> items,
    }) => computeDossierStatus(
      archived: archived,
      manualStatus: manual,
      progress: DossierProgress.fromEvaluations(items),
    );

    test('En préparation si une pièce obligatoire manque ou est à vérifier',
        () {
      expect(
        status(items: [_item(ItemStatus.available), _item(ItemStatus.missing)]),
        DossierStatus.inProgress,
      );
      expect(
        status(items: [_item(ItemStatus.toVerify)]),
        DossierStatus.inProgress,
      );
    });

    test('Prêt à vérifier quand toutes les obligatoires sont disponibles', () {
      expect(
        status(
          items: [
            _item(ItemStatus.available),
            _item(ItemStatus.optional, mandatory: false),
          ],
        ),
        DossierStatus.readyToCheck,
      );
    });

    test('sans pièce obligatoire, le dossier reste en préparation', () {
      expect(status(items: const []), DossierStatus.inProgress);
    });

    test('Terminé uniquement sur confirmation de l’utilisateur', () {
      expect(
        status(
          manual: ManualDossierStatus.completed,
          items: [_item(ItemStatus.missing)],
        ),
        DossierStatus.completed,
      );
    });

    test('Archivé prime sur tout autre statut', () {
      expect(
        status(
          archived: true,
          manual: ManualDossierStatus.completed,
          items: [_item(ItemStatus.available)],
        ),
        DossierStatus.archived,
      );
    });
  });
}
