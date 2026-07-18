/// アプリの画面構成 (IA v2 — docs/21)。
///
/// Bottom Navigationは3タブのみ: Home / Dogs / Settings。
/// - Home = 健康状態と測定の入口(見守りリング)。履歴・日誌はHomeの下の階層。
/// - 測定セッションと結果はタブバーを隠すフルスクリーン遷移(フェード+微スケール)で、
///   「ホーム→測定中→解析→結果」がひとつながりの体験になるようにする。
/// - Dogs = 多頭飼いのカード切り替え(スワイプ)+プロフィール編集。
/// - Settings = デバイス・言語・アカウントなど技術情報の置き場。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/ble/presentation/connect_page.dart';
import '../../features/dogs/domain/dog.dart';
import '../../features/dogs/presentation/dog_profile_page.dart';
import '../../features/dogs/presentation/dogs_page.dart';
import '../../features/error/presentation/error_page.dart';
import '../../features/history/presentation/history_detail_page.dart';
import '../../features/history/presentation/history_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/measurement/domain/measurement.dart';
import '../../features/measurement/presentation/measuring_page.dart';
import '../../features/measurement/presentation/result_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/splash/presentation/splash_page.dart';
import '../navigation/app_shell.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';

  // ---- タブ(3つだけ) ----
  static const home = '/home';
  static const dogs = '/dogs';
  static const settings = '/settings';

  // ---- Homeの下の階層(タブバーは維持) ----
  static const history = '/home/history';
  static const historyDetail = '/home/history/detail';

  // ---- Dogsの下の階層 ----
  static const dogEdit = '/dogs/edit';

  // ---- フルスクリーン(タブバーなし) ----
  static const measureSession = '/measure/session';
  static const measureResult = '/measure/result';
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

      // ---- 3タブShell ----
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          // Home: 状態 → 測定 → 履歴・日誌 がこの枝に住む
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.home,
              builder: (_, __) => const HomePage(),
              routes: [
                GoRoute(
                  path: 'history',
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
              ],
            ),
          ]),
          // Dogs: カードスワイプで切替、編集はこの下
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.dogs,
              builder: (_, __) => const DogsPage(),
              routes: [
                GoRoute(
                  path: 'edit',
                  builder: (_, state) =>
                      DogProfilePage(initial: state.extra as Dog?),
                ),
              ],
            ),
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
