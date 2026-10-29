import 'package:dossia/features/requirements/domain/item_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 10, 29);

  ItemEvaluation eval(
    ItemFacts facts, {
    DateTime? deadline,
  }) => evaluateItem(facts, today: today, dossierDeadline: deadline);

  group('Statut d’une pièce', () {
    test('pièce obligatoire sans document : Manquant', () {
      final e = eval(const ItemFacts(isMandatory: true, quantity: 1));
      expect(e.status, ItemStatus.missing);
      expect(e.isSatisfied, isFalse);
    });

    test('pièce facultative sans document : Facultatif', () {
      final e = eval(const ItemFacts(isMandatory: false, quantity: 1));
      expect(e.status, ItemStatus.optional);
    });

    test('document associé sans condition : Disponible', () {
      final e = eval(
        const ItemFacts(
          isMandatory: true,
          quantity: 1,
          links: [LinkedDocumentFacts(quantityAssigned: 1)],
        ),
      );
      expect(e.status, ItemStatus.available);
      expect(e.isSatisfied, isTrue);
      expect(e.reasons, isEmpty);
    });

    test('pièce facultative associée : Disponible', () {
      final e = eval(
        const ItemFacts(
          isMandatory: false,
          quantity: 1,
          links: [LinkedDocumentFacts(quantityAssigned: 1)],
        ),
      );
      expect(e.status, ItemStatus.available);
    });

    test('condition signalée par l’utilisateur : À vérifier', () {
      final e = eval(
        const ItemFacts(
          isMandatory: true,
          quantity: 1,
          flaggedToVerify: true,
          links: [LinkedDocumentFacts(quantityAssigned: 1)],
        ),
      );
      expect(e.status, ItemStatus.toVerify);
      expect(e.reasons, {VerifyReason.userFlagged});
    });

    test('condition signalée sans document : reste Manquant', () {
      final e = eval(
        const ItemFacts(isMandatory: true, quantity: 1, flaggedToVerify: true),
      );
      expect(e.status, ItemStatus.missing);
    });

    test('quantité insuffisante : À vérifier', () {
      final e = eval(
        const ItemFacts(
          isMandatory: true,
          quantity: 3,
          links: [LinkedDocumentFacts(quantityAssigned: 2)],
        ),
      );
      expect(e.status, ItemStatus.toVerify);
      expect(e.reasons, {VerifyReason.incompleteQuantity});
      expect(e.assignedQuantity, 2);
      expect(e.requiredQuantity, 3);
    });

    test('plusieurs documents couvrent la quantité : Disponible', () {
      final e = eval(
        const ItemFacts(
          isMandatory: true,
          quantity: 2,
          links: [
            LinkedDocumentFacts(quantityAssigned: 1),
            LinkedDocumentFacts(quantityAssigned: 1),
          ],
        ),
      );
      expect(e.status, ItemStatus.available);
      expect(e.assignedQuantity, 2);
    });

    test('document archivé : À vérifier', () {
      final e = eval(
        const ItemFacts(
          isMandatory: true,
          quantity: 1,
          links: [LinkedDocumentFacts(quantityAssigned: 1, archived: true)],
        ),
      );
      expect(e.status, ItemStatus.toVerify);
      expect(e.reasons, {VerifyReason.archivedDocument});
    });

    test('document expiré : À renouveler', () {
      final e = eval(
        ItemFacts(
          isMandatory: true,
          quantity: 1,
          links: [
            LinkedDocumentFacts(
              quantityAssigned: 1,
              expiryDate: DateTime(2026, 10, 28),
            ),
          ],
        ),
      );
      expect(e.status, ItemStatus.toRenew);
      expect(e.isSatisfied, isFalse);
    });

    test('document qui expire aujourd’hui reste valide', () {
      final e = eval(
        ItemFacts(
          isMandatory: true,
          quantity: 1,
          links: [LinkedDocumentFacts(quantityAssigned: 1, expiryDate: today)],
        ),
      );
      expect(e.status, ItemStatus.available);
    });

    test('À renouveler l’emporte sur À vérifier', () {
      final e = eval(
        ItemFacts(
          isMandatory: true,
          quantity: 2,
          links: [
            LinkedDocumentFacts(
              quantityAssigned: 1,
              expiryDate: DateTime(2025, 1, 1),
            ),
          ],
        ),
      );
      expect(e.status, ItemStatus.toRenew);
      expect(e.reasons, contains(VerifyReason.incompleteQuantity));
    });

    test('document qui expire avant la date limite du dossier : À vérifier', () {
      final e = eval(
        ItemFacts(
          isMandatory: true,
          quantity: 1,
          links: [
            LinkedDocumentFacts(
              quantityAssigned: 1,
              expiryDate: DateTime(2026, 11, 15),
            ),
          ],
        ),
        deadline: DateTime(2026, 12, 1),
      );
      expect(e.status, ItemStatus.toVerify);
      expect(e.reasons, {VerifyReason.expiresBeforeDeadline});
    });

    test('aucune date d’expiration n’est supposée', () {
      final e = eval(
        const ItemFacts(
          isMandatory: true,
          quantity: 1,
          links: [LinkedDocumentFacts(quantityAssigned: 1)],
        ),
        deadline: DateTime(2030, 1, 1),
      );
      expect(e.status, ItemStatus.available);
    });

    test('libellés de statut', () {
      expect(ItemStatus.missing.label, 'Manquant');
      expect(ItemStatus.available.label, 'Disponible');
      expect(ItemStatus.toVerify.label, 'À vérifier');
      expect(ItemStatus.toRenew.label, 'À renouveler');
      expect(ItemStatus.optional.label, 'Facultatif');
    });
  });
}
