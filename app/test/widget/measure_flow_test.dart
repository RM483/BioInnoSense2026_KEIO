/// 測定フロー(開始→測定中→結果)のWidgetテスト。
/// MockBleRepositoryを実物として使い、FakeAsync下でタイマーを進めて検証する。
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
import 'package:hydropaw/features/measurement/presentation/measure_start_page.dart';
import 'package:hydropaw/features/measurement/presentation/measuring_page.dart';
import 'package:hydropaw/features/measurement/presentation/result_page.dart';
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
      GoRoute(
          path: '/measure', builder: (_, __) => const MeasureStartPage()),
      GoRoute(
          path: '/measure/session',
          builder: (_, __) => const MeasuringPage()),
      GoRoute(
          path: '/measure/result', builder: (_, __) => const ResultPage()),
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

/// FakeAsync下でMockの遅延(接続700ms等)とUI更新を進めるヘルパ
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
        tester.element(find.byType(MeasureStartPage)));
    final f =
        container.read(bleControllerProvider.notifier).connect('mock-1');
    await settle(tester, const Duration(milliseconds: 800));
    await f;
    await tester.pump();
  }

  Future<void> teardownBle(WidgetTester tester, Type pageType) async {
    final container =
        ProviderScope.containerOf(tester.element(find.byType(pageType)));
    final stop =
        container.read(bleControllerProvider.notifier).disconnect();
    await settle(tester, const Duration(milliseconds: 100));
    await stop;
  }

  testWidgets('開始→測定中: Mockデータが表示され、1Hzで更新される', (tester) async {
    await dogs.addDog(const Dog(id: '', name: 'ポチ'));
    await tester.pumpWidget(
        harness(ble: ble, dogs: dogs, measurements: measurements));
    await tester.pump();
    await connectBle(tester);

    expect(find.text('準備ができました'), findsNothing); // 文言はヒント側
    await tester.tap(find.text('はじめる'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 自動で測定開始(ACK) → サンプル到着
    await settle(tester, const Duration(milliseconds: 100));
    await settle(tester, const Duration(milliseconds: 1100));
    await settle(tester, const Duration(milliseconds: 1100));

    final v1 =
        tester.widget<Text>(find.byKey(const ValueKey('h2-value'))).data;
    expect(v1, isNotNull);
    expect(find.textContaining('ウォームアップ'), findsOneWidget);

    await settle(tester, const Duration(milliseconds: 1100));
    final v2 =
        tester.widget<Text>(find.byKey(const ValueKey('h2-value'))).data;
    expect(v2 == v1, isFalse); // 1Hzで値が動いている

    await teardownBle(tester, MeasuringPage);
  });

  testWidgets('終了→結果画面へ遷移し、保存される(意味の言葉で表示)', (tester) async {
    await dogs.addDog(const Dog(id: '', name: 'ポチ'));
    await tester.pumpWidget(
        harness(ble: ble, dogs: dogs, measurements: measurements));
    await tester.pump();
    await connectBle(tester);

    await tester.tap(find.text('はじめる'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester, const Duration(milliseconds: 100));
    await settle(tester, const Duration(milliseconds: 2200));

    await tester.tap(find.text('終了する'));
    await settle(tester, const Duration(milliseconds: 300)); // ACK+summary
    await settle(tester, const Duration(milliseconds: 700)); // 遷移完了

    expect(find.text('測定できました'), findsOneWidget);
    expect(measurements.saved, hasLength(1)); // Firestore(メモリ)に保存済み
    expect(find.text('ホームに戻る'), findsOneWidget);

    await teardownBle(tester, ResultPage);
  });

  testWidgets('犬未登録: 開始できず登録導線が出る(クラッシュしない)', (tester) async {
    await tester.pumpWidget(
        harness(ble: ble, dogs: dogs, measurements: measurements));
    await tester.pump();
    await connectBle(tester);

    expect(find.text('はじめる'), findsNothing);
    expect(find.text('愛犬を登録する'), findsWidgets); // 導線
    await teardownBle(tester, MeasureStartPage);
  });

  testWidgets('測定中のBLE切断で再接続表示、再接続後も測定画面が継続する', (tester) async {
    await dogs.addDog(const Dog(id: '', name: 'ポチ'));
    await tester.pumpWidget(
        harness(ble: ble, dogs: dogs, measurements: measurements));
    await tester.pump();
    await connectBle(tester);

    await tester.tap(find.text('はじめる'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester, const Duration(milliseconds: 1200));

    // ---- 切断 → 再接続中の表示(青探索アイコン) ----
    final disc = ble.disconnect();
    await settle(tester, const Duration(milliseconds: 100));
    await disc;
    await tester.pump();
    expect(find.byIcon(Icons.bluetooth_searching), findsOneWidget);

    // ---- バックオフ1s → 自動再接続 ----
    await settle(tester, const Duration(milliseconds: 1100));
    await settle(tester, const Duration(milliseconds: 800));
    await settle(tester, const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.bluetooth_searching), findsNothing);
    // 測定画面が保たれている
    expect(find.text('終了する'), findsOneWidget);
    expect(find.byKey(const ValueKey('h2-value')), findsOneWidget);

    await teardownBle(tester, MeasuringPage);
  });

  testWidgets('ダークモードでホーム・測定タブが崩れない', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await dogs.addDog(
        const Dog(id: '', name: 'ポチ', breed: '柴犬', weightKg: 8.2));

    await tester.pumpWidget(harness(
        ble: ble,
        dogs: dogs,
        measurements: measurements,
        initialLocation: '/home',
        themeMode: ThemeMode.dark));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    expect(find.text('ポチ'), findsOneWidget);
    expect(find.text('はじめての測定をしてみましょう'), findsOneWidget); // 意味の言葉

    await tester.pumpWidget(harness(
        ble: MockBleRepository(seed: 2),
        dogs: dogs,
        measurements: measurements,
        initialLocation: '/measure',
        themeMode: ThemeMode.dark));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    expect(find.byType(MeasureStartPage), findsOneWidget);
  });
}
