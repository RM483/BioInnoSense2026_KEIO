/// 測定フロー(ホーム→測定中→結果)のWidgetテスト (IA v2: ホーム=測定の入口)。
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
import 'package:hydropaw/features/measurement/presentation/measuring_page.dart';
import 'package:hydropaw/features/measurement/presentation/result_page.dart';
import 'package:hydropaw/features/records/data/care_note_repository.dart';
import 'package:hydropaw/features/settings/data/user_settings_repository.dart';
import 'package:hydropaw/l10n/app_localizations.dart';

Widget harness({
  required MockBleRepository ble,
  required InMemoryDogRepository dogs,
  required InMemoryMeasurementRepository measurements,
  String initialLocation = '/home',
  ThemeMode themeMode = ThemeMode.light,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HomePage()),
      GoRoute(
          path: '/measure/session',
          builder: (_, __) => const MeasuringPage()),
      GoRoute(
          path: '/measure/result', builder: (_, __) => const ResultPage()),
      GoRoute(
          path: '/error',
          builder: (_, s) =>
              ErrorPage(kind: s.extra as ErrorKind? ?? ErrorKind.unknown)),
      GoRoute(path: '/dogs', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/connect', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/home/history', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/settings', builder: (_, __) => const Scaffold()),
    ],
  );
  return ProviderScope(
    overrides: [
      bleRepositoryProvider.overrideWithValue(ble),
      dogRepositoryProvider.overrideWithValue(dogs),
      measurementRepositoryProvider.overrideWithValue(measurements),
      careNoteRepositoryProvider
          .overrideWith((ref) => InMemoryCareNoteRepository()),
      // 初回頭数質問はスキップ(上限2頭で固定)
      userSettingsRepositoryProvider.overrideWith(
          (ref) => InMemoryUserSettingsRepository(initialMaxDogs: 2)),
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
        tester.element(find.byType(HomePage)));
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

    // ホームのCTA(名前入り) → 対象犬の確認 → セッションへ (v2.1 §3)
    await tester.tap(find.text('ポチの測定をはじめる').last);
    await tester.pumpAndSettle();
    expect(find.text('ポチを測定します'), findsOneWidget);
    await tester.tap(find.text('測定を開始'));
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

  testWidgets('呼気セッション: 自動で解析→結果へ遷移し、品質つきで保存される',
      (tester) async {
    await dogs.addDog(const Dog(id: '', name: 'ポチ'));
    await tester.pumpWidget(
        harness(ble: ble, dogs: dogs, measurements: measurements));
    await tester.pump();
    await connectBle(tester);

    await tester.tap(find.text('ポチの測定をはじめる').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('測定を開始'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester, const Duration(milliseconds: 100));

    // Mockの呼気タイムライン(約18s)をFWの実況どおり進める。
    // ユーザー操作なしで WARMUP→READY→呼気→解析→結果 が完結する。
    for (var i = 0; i < 20; i++) {
      await settle(tester, const Duration(milliseconds: 1000));
      if (find.text('測定できました').evaluate().isNotEmpty) break;
    }
    await settle(tester, const Duration(milliseconds: 700)); // 遷移完了

    expect(find.text('測定できました'), findsOneWidget);
    expect(measurements.saved, hasLength(1)); // Firestore(メモリ)に保存済み
    expect(measurements.saved.first.quality, greaterThanOrEqualTo(80));
    expect(measurements.saved.first.mode, 'breath');
    expect(find.textContaining('測定の質'), findsOneWidget); // 品質の言葉化
    expect(find.text('ホームに戻る'), findsOneWidget);

    await teardownBle(tester, ResultPage);
  });

  testWidgets('犬未登録: 開始できず登録導線が出る(クラッシュしない)', (tester) async {
    await tester.pumpWidget(
        harness(ble: ble, dogs: dogs, measurements: measurements));
    await tester.pump();
    await connectBle(tester);

    expect(find.textContaining('測定をはじめる'), findsNothing);
    // 空状態: 見守り中の犬がいない (§8)
    expect(find.text('現在見守っている犬はいません'), findsOneWidget);
    expect(find.text('愛犬を登録する'), findsWidgets); // 導線
    await teardownBle(tester, HomePage);
  });

  testWidgets('測定中のBLE切断で再接続表示、再接続後も測定画面が継続する', (tester) async {
    await dogs.addDog(const Dog(id: '', name: 'ポチ'));
    await tester.pumpWidget(
        harness(ble: ble, dogs: dogs, measurements: measurements));
    await tester.pump();
    await connectBle(tester);

    await tester.tap(find.text('ポチの測定をはじめる').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('測定を開始'));
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
    // 測定画面が保たれている(呼気モードのボタンは「中止する」)
    expect(find.text('中止する'), findsOneWidget);
    expect(find.byKey(const ValueKey('h2-value')), findsOneWidget);

    await teardownBle(tester, MeasuringPage);
  });

  testWidgets('ダークモード・スマホ画面幅でホームが崩れない', (tester) async {
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
    // 1段目=名前入り主CTA / 2段目=副導線 (v2.1 §1,3)
    expect(find.text('ポチの測定をはじめる'), findsWidgets);
    expect(find.text('履歴を見る'), findsOneWidget);
    expect(find.text('きょうの記録'), findsOneWidget);
  });
}
