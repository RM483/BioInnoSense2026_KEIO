/// 測定フローのWidgetテスト (MockBleRepositoryを実物として使用)。
/// FakeAsync下でMockのタイマーを進めながらUIを検証する。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hydropaw/core/analytics/app_analytics.dart';
import 'package:hydropaw/core/dev/offline_overrides.dart';
import 'package:hydropaw/core/theme/app_theme.dart';
import 'package:hydropaw/features/ble/application/ble_controller.dart';
import 'package:hydropaw/features/ble/data/ble_service.dart';
import 'package:hydropaw/features/ble/data/mock_ble_repository.dart';
import 'package:hydropaw/features/dogs/data/dog_repository.dart';
import 'package:hydropaw/features/dogs/domain/dog.dart';
import 'package:hydropaw/features/error/presentation/error_page.dart';
import 'package:hydropaw/features/home/presentation/home_page.dart';
import 'package:hydropaw/features/measurement/data/measurement_repository.dart';
import 'package:hydropaw/features/measurement/presentation/measure_page.dart';
import 'package:hydropaw/l10n/app_localizations.dart';

Widget harness({
  required MockBleRepository ble,
  required InMemoryDogRepository dogs,
  required InMemoryMeasurementRepository measurements,
  String initialLocation = '/measure',
  ThemeMode themeMode = ThemeMode.light,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HomePage()),
      GoRoute(path: '/measure', builder: (_, __) => const MeasurePage()),
      GoRoute(
          path: '/error',
          builder: (_, s) =>
              ErrorPage(kind: s.extra as ErrorKind? ?? ErrorKind.unknown)),
      GoRoute(path: '/dog', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/connect', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/history', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/settings', builder: (_, __) => const Scaffold()),
    ],
  );
  return ProviderScope(
    overrides: [
      bleRepositoryProvider.overrideWithValue(ble),
      dogRepositoryProvider.overrideWithValue(dogs),
      measurementRepositoryProvider.overrideWithValue(measurements),
      appAnalyticsProvider.overrideWithValue(const NoopAnalytics()),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja')],
      locale: const Locale('ja'),
    ),
  );
}

/// FakeAsync下でMockの遅延(接続700ms等)を完了させるヘルパ
Future<void> settle(WidgetTester tester, Duration d) async {
  await tester.pump(d);
  await tester.pump();
}

void main() {
  late MockBleRepository ble;
  late InMemoryDogRepository dogs;
  late InMemoryMeasurementRepository measurements;

  setUp(() {
    ble = MockBleRepository(seed: 1);
    dogs = InMemoryDogRepository();
    measurements = InMemoryMeasurementRepository();
  });

  Future<void> connectBle(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
        tester.element(find.byType(MeasurePage)));
    final f =
        container.read(bleControllerProvider.notifier).connect('mock-1');
    await settle(tester, const Duration(milliseconds: 800));
    await f;
    await tester.pump();
  }

  testWidgets('Mockデータが測定画面に表示され、値が更新される', (tester) async {
    await dogs.addDog(const Dog(id: '', name: 'ポチ'));
    await tester.pumpWidget(
        harness(ble: ble, dogs: dogs, measurements: measurements));
    await tester.pump();

    await connectBle(tester);
    expect(find.text('接続中'), findsOneWidget);

    // 測定開始
    await tester.tap(find.text('測定をはじめる'));
    await settle(tester, const Duration(milliseconds: 100)); // ACK
    // 2サンプル分進める
    await settle(tester, const Duration(milliseconds: 1100));
    await settle(tester, const Duration(milliseconds: 1100));

    expect(find.text('––'), findsNothing); // 現在値が表示されている
    expect(find.text('停止'), findsOneWidget);
    expect(find.textContaining('ウォームアップ'), findsOneWidget);

    // さらに1秒進めると値が更新される
    final before =
        tester.widget<Text>(find.byKey(const ValueKey('h2-value'))).data;
    await settle(tester, const Duration(milliseconds: 1100));
    final after =
        tester.widget<Text>(find.byKey(const ValueKey('h2-value'))).data;
    expect(after, isNot('––'));
    expect(after == before, isFalse); // 値が動いている

    // 後始末(タイマー停止)
    final container = ProviderScope.containerOf(
        tester.element(find.byType(MeasurePage)));
    final stop = container
        .read(bleControllerProvider.notifier)
        .disconnect();
    await settle(tester, const Duration(milliseconds: 100));
    await stop;
  });

  testWidgets('犬未登録では開始できず、登録導線が出る(クラッシュしない)', (tester) async {
    await tester.pumpWidget(
        harness(ble: ble, dogs: dogs, measurements: measurements));
    await tester.pump();
    await connectBle(tester);

    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '測定をはじめる'));
    expect(button.onPressed, isNull); // 開始不可(空dogId保存が起き得ない)
    expect(find.textContaining('プロフィールを登録'), findsOneWidget);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(MeasurePage)));
    final stop =
        container.read(bleControllerProvider.notifier).disconnect();
    await settle(tester, const Duration(milliseconds: 100));
    await stop;
  });

  testWidgets('BLE切断で再接続表示になり、再接続後に測定画面が復帰する', (tester) async {
    await dogs.addDog(const Dog(id: '', name: 'ポチ'));
    await tester.pumpWidget(
        harness(ble: ble, dogs: dogs, measurements: measurements));
    await tester.pump();
    await connectBle(tester);

    await tester.tap(find.text('測定をはじめる'));
    await settle(tester, const Duration(milliseconds: 100));
    await settle(tester, const Duration(milliseconds: 1100));
    expect(find.text('停止'), findsOneWidget);

    // ---- 切断 → 再接続表示 ----
    final disc = ble.disconnect();
    await settle(tester, const Duration(milliseconds: 100));
    await disc;
    await tester.pump();
    expect(find.text('再接続中…'), findsOneWidget);

    // ---- 指数バックオフ(1s) → 自動再接続(接続700ms) ----
    await settle(tester, const Duration(milliseconds: 1100));
    await settle(tester, const Duration(milliseconds: 800));
    await settle(tester, const Duration(milliseconds: 200));
    expect(find.text('接続中'), findsOneWidget);
    // 測定画面が保たれている(値・停止ボタンが残存)
    expect(find.text('停止'), findsOneWidget);
    expect(find.text('––'), findsNothing);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(MeasurePage)));
    final stop =
        container.read(bleControllerProvider.notifier).disconnect();
    await settle(tester, const Duration(milliseconds: 100));
    await stop;
  });

  testWidgets('ダークモードで測定画面・ホームが崩れない(オーバーフローなし)', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532); // iPhone級
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await dogs.addDog(const Dog(
        id: '', name: 'ポチ', breed: '柴犬', weightKg: 8.2));

    // 測定画面(ダーク)
    await tester.pumpWidget(harness(
        ble: ble,
        dogs: dogs,
        measurements: measurements,
        themeMode: ThemeMode.dark));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(MeasurePage), findsOneWidget);

    // ホーム(ダーク)
    await tester.pumpWidget(harness(
        ble: MockBleRepository(seed: 2),
        dogs: dogs,
        measurements: measurements,
        initialLocation: '/home',
        themeMode: ThemeMode.dark));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('ポチ'), findsOneWidget);
  });
}
