/// アプリの画面構成。
///
/// 5タブ(ホーム/測定/履歴/愛犬/設定)のShell + 測定セッションと結果は
/// タブバーを隠すフルスクリーン遷移(フェード+わずかなスケール)で、
/// 「開始→測定中→完了→結果」がひとつながりの体験になるようにする。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/ble/presentation/connect_page.dart';
import '../../features/dogs/presentation/dog_profile_page.dart';
import '../../features/error/presentation/error_page.dart';
import '../../features/history/presentation/history_detail_page.dart';
import '../../features/history/presentation/history_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/measurement/domain/measurement.dart';
import '../../features/measurement/presentation/measure_start_page.dart';
import '../../features/measurement/presentation/measuring_page.dart';
import '../../features/measurement/presentation/result_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/splash/presentation/splash_page.dart';
import '../navigation/app_shell.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const home = '/home';
  static const measure = '/measure';
  static const measureSession = '/measure/session';
  static const measureResult = '/measure/result';
  static const history = '/history';
  static const historyDetail = '/history/detail';
  static const dog = '/dog';
  static const settings = '/settings';
  static const connect = '/connect';
  static const error = '/error';
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  // 認証状態の変化でGoRouterのredirectを再評価させる
  final refresh = ValueNotifier(0);
  ref
    ..onDispose(refresh.dispose)
    ..listen(authStateChangesProvider, (_, __) => refresh.value++);
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final user = ref.read(authStateChangesProvider).valueOrNull;
      final loggingIn = state.matchedLocation == Routes.login;
      final splashing = state.matchedLocation == Routes.splash;
      if (splashing) return null; // Splashが自分で遷移する
      if (user == null && !loggingIn) return Routes.login;
      if (user != null && loggingIn) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const SplashPage()),
      GoRoute(path: Routes.login, builder: (_, __) => const LoginPage()),

      // ---- 5タブShell ----
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, __) => const HomePage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: Routes.measure,
                builder: (_, __) => const MeasureStartPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.history,
              builder: (_, __) => const HistoryPage(),
              routes: [
                GoRoute(
                  path: 'detail',
                  pageBuilder: (_, state) => _fadeScale(
                      state,
                      HistoryDetailPage(
                          measurement: state.extra as Measurement)),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: Routes.dog,
                builder: (_, __) => const DogProfilePage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: Routes.settings,
                builder: (_, __) => const SettingsPage()),
          ]),
        ],
      ),

      // ---- フルスクリーン(タブバーなし): 測定セッション → 結果 ----
      GoRoute(
        path: Routes.measureSession,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (_, state) => _fadeScale(state, const MeasuringPage()),
      ),
      GoRoute(
        path: Routes.measureResult,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (_, state) => _fadeScale(state, const ResultPage()),
      ),

      // ---- 補助画面 ----
      GoRoute(
        path: Routes.connect,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const ConnectPage(),
      ),
      GoRoute(
        path: Routes.error,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) =>
            ErrorPage(kind: state.extra as ErrorKind? ?? ErrorKind.unknown),
      ),
    ],
  );
});

/// 静かな画面遷移: フェード + ごくわずかなスケール(0.97→1.0)。
CustomTransitionPage<T> _fadeScale<T>(GoRouterState state, Widget child) =>
    CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
