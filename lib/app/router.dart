import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/deadlines/presentation/deadlines_screen.dart';
import '../features/documents/presentation/document_detail_screen.dart';
import '../features/documents/presentation/document_form_screen.dart';
import '../features/documents/presentation/documents_screen.dart';
import '../features/dossiers/presentation/dossier_detail_screen.dart';
import '../features/dossiers/presentation/dossier_form_screen.dart';
import '../features/dossiers/presentation/dossiers_screen.dart';
import '../features/onboarding/presentation/inventory_screen.dart';
import '../features/onboarding/presentation/welcome_screen.dart';
import '../features/requirements/presentation/reorder_requirements_screen.dart';
import '../features/requirements/presentation/requirement_detail_screen.dart';
import '../features/requirements/presentation/requirement_form_screen.dart';
import '../features/settings/presentation/backup_screen.dart';
import '../features/settings/presentation/privacy_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'shell.dart';

/// Chemins de l'application.
abstract final class Routes {
  static const welcome = '/welcome';
  static const inventory = '/inventory';
  static const home = '/home';
  static const dossiers = '/dossiers';
  static const documents = '/documents';
  static const settings = '/settings';
  static const deadlines = '/deadlines';
  static const backup = '/backup';
  static const privacy = '/privacy';

  static const newDossier = '/dossier/new';
  static String dossier(String id) => '/dossier/$id';
  static String editDossier(String id) => '/dossier/$id/edit';
  static String reorderItems(String id) => '/dossier/$id/reorder';
  static String newItem(String dossierId) => '/dossier/$dossierId/item/new';
  static String item(String dossierId, String itemId) =>
      '/dossier/$dossierId/item/$itemId';
  static String editItem(String dossierId, String itemId) =>
      '/dossier/$dossierId/item/$itemId/edit';

  /// [typeId] pré-remplit le type ; [linkItemId] associe le document créé à
  /// cette pièce.
  static String newDocument({String? typeId, String? linkItemId}) => Uri(
    path: '/document/new',
    queryParameters: {
      'typeId': ?typeId,
      'linkItem': ?linkItemId,
    },
  ).toString();
  static String document(String id) => '/document/$id';
  static String editDocument(String id) => '/document/$id/edit';
}

/// Emplacement initial, fixé au démarrage selon l'état de l'onboarding.
final initialLocationProvider = Provider<String>((ref) => Routes.home);

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: ref.watch(initialLocationProvider),
    routes: [
      GoRoute(
        path: Routes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: Routes.inventory,
        builder: (context, state) => InventoryScreen(
          fromOnboarding: state.uri.queryParameters['onboarding'] == '1',
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.dossiers,
                builder: (context, state) => const DossiersScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.documents,
                builder: (context, state) => const DocumentsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.deadlines,
        builder: (context, state) => const DeadlinesScreen(),
      ),
      GoRoute(
        path: Routes.backup,
        builder: (context, state) => const BackupScreen(),
      ),
      GoRoute(
        path: Routes.privacy,
        builder: (context, state) => const PrivacyScreen(),
      ),
      GoRoute(
        path: Routes.newDossier,
        builder: (context, state) => const DossierFormScreen(),
      ),
      GoRoute(
        path: '/dossier/:id',
        builder: (context, state) =>
            DossierDetailScreen(dossierId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                DossierFormScreen(dossierId: state.pathParameters['id']),
          ),
          GoRoute(
            path: 'reorder',
            builder: (context, state) => ReorderRequirementsScreen(
              dossierId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: 'item/new',
            builder: (context, state) =>
                RequirementFormScreen(dossierId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'item/:itemId',
            builder: (context, state) => RequirementDetailScreen(
              dossierId: state.pathParameters['id']!,
              itemId: state.pathParameters['itemId']!,
            ),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => RequirementFormScreen(
                  dossierId: state.pathParameters['id']!,
                  itemId: state.pathParameters['itemId'],
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/document/new',
        builder: (context, state) => DocumentFormScreen(
          initialTypeId: state.uri.queryParameters['typeId'],
          linkToItemId: state.uri.queryParameters['linkItem'],
        ),
      ),
      GoRoute(
        path: '/document/:id',
        builder: (context, state) =>
            DocumentDetailScreen(documentId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                DocumentFormScreen(documentId: state.pathParameters['id']),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
