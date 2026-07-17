/// GoRouterによる宣言的ルーティング。認証状態でリダイレクトする。
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/ble/presentation/connect_page.dart';
import '../../features/dogs/presentation/dog_profile_page.dart';
import '../../features/error/presentation/error_page.dart';
import '../../features/history/presentation/history_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/measurement/presentation/measure_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/splash/presentation/splash_page.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const home = '/home';
  static const connect = '/connect';
  static const measure = '/measure';
  static const history = '/history';
  static const dog = '/dog';
  static const settings = '/settings';
  static const error = '/error';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // 認証状態の変化でGoRouterのredirectを再評価させる
  final refresh = ValueNotifier(0);
  ref
    ..onDispose(refresh.dispose)
    ..listen(authStateChangesProvider, (_, __) => refresh.value++);
  return GoRouter(
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
      GoRoute(path: Routes.home, builder: (_, __) => const HomePage()),
      GoRoute(path: Routes.connect, builder: (_, __) => const ConnectPage()),
      GoRoute(path: Routes.measure, builder: (_, __) => const MeasurePage()),
      GoRoute(path: Routes.history, builder: (_, __) => const HistoryPage()),
      GoRoute(path: Routes.dog, builder: (_, __) => const DogProfilePage()),
      GoRoute(path: Routes.settings, builder: (_, __) => const SettingsPage()),
      GoRoute(
        path: Routes.error,
        builder: (_, state) =>
            ErrorPage(kind: state.extra as ErrorKind? ?? ErrorKind.unknown),
      ),
    ],
  );
});

