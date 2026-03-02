import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/auth/auth_provider.dart';
import '../features/auth/pages/login_page.dart';
import '../features/auth/pages/register_page.dart';
import '../features/home/pages/home_page.dart';
import '../features/home/pages/material_detail_page.dart';
import '../features/inspiration/pages/inspiration_page.dart';
import '../features/moments/pages/moments_page.dart';
import '../features/moments/pages/moment_detail_page.dart';
import '../features/profile/pages/profile_page.dart';
import '../features/profile/pages/membership_page.dart';
import '../features/profile/pages/my_list_page.dart';
import '../features/profile/pages/change_password_page.dart';
import 'main_scaffold.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final isUnauthenticated =
          authState.status == AuthStatus.unauthenticated;
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
      // Material detail
      GoRoute(
        path: '/material/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return MaterialDetailPage(materialId: id);
        },
      ),
      // Moment detail
      GoRoute(
        path: '/moment/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return MomentDetailPage(momentId: id);
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

