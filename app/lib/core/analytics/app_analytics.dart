/// Analyticsの薄い抽象。
/// Firebase未設定(オフライン/Mock開発・テスト)では NoopAnalytics に
/// 差し替えることで、計測コードがクラッシュ源にならないようにする。
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../firebase/firebase_providers.dart';

abstract interface class AppAnalytics {
  Future<void> logEvent(String name, [Map<String, Object>? parameters]);
}

class FirebaseAppAnalytics implements AppAnalytics {
  const FirebaseAppAnalytics(this._ref);
  final Ref _ref;

  @override
  Future<void> logEvent(String name, [Map<String, Object>? parameters]) =>
      _ref.read(analyticsProvider).logEvent(name: name, parameters: parameters);
}

class NoopAnalytics implements AppAnalytics {
  const NoopAnalytics();

  @override
  Future<void> logEvent(String name, [Map<String, Object>? parameters]) async {}
}

final appAnalyticsProvider =
    Provider<AppAnalytics>((ref) => FirebaseAppAnalytics(ref));
