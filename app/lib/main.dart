/// HydroPaw エントリポイント。
/// Firebase初期化とグローバル例外ハンドラ(Crashlytics)を構成する。
///
/// Firebaseが未設定(firebase_options / google-services.json なし)でも、
/// Mockモード(--dart-define=USE_MOCK_BLE=true)ならオフラインDIに
/// フォールバックしてクラッシュせずに起動する — 実機なしのUI開発・デモ用。
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'app.dart';
import 'core/dev/offline_overrides.dart';
import 'features/ble/data/ble_service.dart' show kUseMockBle;

bool _crashlyticsReady = false;

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    final firebaseReady = await _initFirebase();

    if (firebaseReady) {
      // Flutterフレームワーク内の例外 → Crashlytics
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      // フレームワーク外(プラットフォーム)の例外 → Crashlytics
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      _crashlyticsReady = true;
    }

    runApp(ProviderScope(
      overrides: firebaseReady ? const [] : offlineOverrides(),
      child: const HydroPawApp(),
    ));
  }, (error, stack) {
    if (_crashlyticsReady) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } else {
      debugPrint('Uncaught: $error\n$stack');
    }
  });
}

/// Firebaseを初期化する。設定ファイルが無い環境では:
/// - Mockモード → false を返しオフラインDIで続行
/// - 本番モード → 設定漏れは致命的なのでそのままthrow
Future<bool> _initFirebase() async {
  try {
    // firebase_options.dart は `flutterfire configure` で生成する
    // (ネイティブ設定ファイルからの自動解決に依存)。
    await Firebase.initializeApp();
    return true;
  } catch (e) {
    if (kUseMockBle) {
      debugPrint('Firebase未設定のためオフラインモードで起動します: $e');
      return false;
    }
    rethrow;
  }
}
