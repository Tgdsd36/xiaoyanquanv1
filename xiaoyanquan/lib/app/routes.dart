import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/auth/auth_provider.dart';
import '../features/auth/pages/login_page.dart';
import '../features/auth/pages/register_page.dart';
import '../features/home/pages/home_page.dart';
import '../features/home/pages/material_detail_page.dart';
import '../features/home/pages/material_preview_page.dart';
import '../features/home/models/material_model.dart'; // ignore: unused_import
import '../features/home/pages/search_page.dart'; // SearchArgs
import '../features/inspiration/pages/inspiration_page.dart';
import '../features/moments/pages/moments_page.dart';
import '../features/profile/pages/profile_page.dart';
import '../features/profile/pages/membership_page.dart';
import '../features/profile/pages/my_list_page.dart';
import '../features/profile/pages/favorite_group_detail_page.dart';
import '../features/profile/pages/change_password_page.dart';
import 'main_scaffold.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authStatus = ref.watch(authProvider.select((state) => state.status));

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final isUnauthenticated = authStatus == AuthStatus.unauthenticated;
      final isLoginRoute = state.matchedLocation == '/login';

      if (isUnauthenticated && !isLoginRoute) return '/login';
      if (!isUnauthenticated && isLoginRoute) return '/';
      return null;
    },
    routes: [
      // Login
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      // Register
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      // Search
      GoRoute(
        path: '/search',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as SearchArgs?;
          return SearchPage(args: args);
        },
      ),
      // Material preview (full-screen image/video)
      GoRoute(
        path: '/material/:id/preview',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          final extra = state.extra;
          // 兼容旧的 MaterialListItem 传参和新的 MaterialPreviewArgs
          if (extra is MaterialPreviewArgs) {
            return MaterialPreviewPage(
              materialId: id,
              initialItem: extra.initialItem,
              imageUrls: extra.imageUrls,
              initialIndex: extra.initialIndex,
              titleOverride: extra.title,
            );
          }
          final item = extra as MaterialListItem?;
          return MaterialPreviewPage(materialId: id, initialItem: item);
        },
      ),
      // Material detail
      GoRoute(
        path: '/material/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return MaterialDetailPage(materialId: id);
        },
      ),
      // Membership
      GoRoute(
        path: '/membership',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const MembershipPage(),
      ),
      // My favorites
      GoRoute(
        path: '/my-favorites',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            const MyListPage(type: MyListType.favorites),
      ),
      // Favorite group detail
      GoRoute(
        path: '/favorite-group/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          final name = state.extra as String? ?? '';
          return FavoriteGroupDetailPage(groupId: id, groupName: name);
        },
      ),
      // My downloads
      GoRoute(
        path: '/my-downloads',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            const MyListPage(type: MyListType.downloads),
      ),
      // My questions
      GoRoute(
        path: '/my-questions',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            const MyListPage(type: MyListType.questions),
      ),
      // Change password
      GoRoute(
        path: '/change-password',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ChangePasswordPage(),
      ),
      // Main tabs
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const HomePage(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/inspiration',
              builder: (context, state) => const InspirationPage(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/moments',
              builder: (context, state) => const MomentsPage(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfilePage(),
            ),
          ]),
        ],
      ),
    ],
  );
});
