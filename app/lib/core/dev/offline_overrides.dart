/// Firebase未設定環境(実機なしのMock開発・デモ)向けのDIオーバーライド。
///
/// main.dart で Firebase.initializeApp() が失敗した場合にのみ適用され、
/// 認証・犬プロフィール・測定履歴をすべてメモリ上で完結させる。
/// アプリの画面・Controller・BLE層は一切変更せずに全画面が動作する。
import 'dart:async';
import 'dart:typed_data';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/dogs/data/dog_repository.dart';
import '../../features/dogs/domain/dog.dart';
import '../../features/measurement/data/measurement_repository.dart';
import '../../features/measurement/domain/measurement.dart';
import '../../features/records/data/care_note_repository.dart';
import '../../features/records/domain/care_note.dart';
import '../../features/settings/data/user_settings_repository.dart';
import '../analytics/app_analytics.dart';

/// Firebase不在時のオーバーライド一式。
List<Override> offlineOverrides() {
  final auth = InMemoryAuthRepository();
  return [
    authRepositoryProvider.overrideWithValue(auth),
    dogRepositoryProvider.overrideWith((ref) => InMemoryDogRepository()),
    measurementRepositoryProvider
        .overrideWith((ref) => InMemoryMeasurementRepository()),
    careNoteRepositoryProvider
        .overrideWith((ref) => InMemoryCareNoteRepository()),
    userSettingsRepositoryProvider
        .overrideWith((ref) => InMemoryUserSettingsRepository()),
    appAnalyticsProvider.overrideWithValue(const NoopAnalytics()),
  ];
}

class InMemoryUserSettingsRepository implements UserSettingsRepository {
  InMemoryUserSettingsRepository({int? initialMaxDogs})
      : _maxDogs = initialMaxDogs;

  final _controller = StreamController<int?>.broadcast();
  int? _maxDogs;

  @override
  Stream<int?> watchMaxDogs() async* {
    yield _maxDogs;
    yield* _controller.stream;
  }

  @override
  Future<void> setMaxDogs(int value) async {
    _maxDogs = value;
    _controller.add(value);
  }
}

class InMemoryAuthRepository implements AuthRepository {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _user;

  @override
  Stream<AppUser?> watchAuthState() async* {
    yield _user;
    yield* _controller.stream;
  }

  AppUser _signIn(AppUser user) {
    _user = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<AppUser> signInWithEmail(String email, String password) async =>
      _signIn(AppUser(uid: 'offline-user', email: email));

  @override
  Future<AppUser> signUpWithEmail(String email, String password) async =>
      _signIn(AppUser(uid: 'offline-user', email: email));

  @override
  Future<AppUser> signInAnonymously() async =>
      _signIn(const AppUser(uid: 'offline-user', isAnonymous: true));

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }
}

class InMemoryDogRepository implements DogRepository {
  final _controller = StreamController<List<Dog>>.broadcast();
  final _dogs = <Dog>[];
  int _nextId = 1;

  void _notify() => _controller.add(List.unmodifiable(_dogs));

  @override
  Stream<List<Dog>> watchDogs() async* {
    yield List.unmodifiable(_dogs);
    yield* _controller.stream;
  }

  @override
  Future<String> addDog(Dog dog) async {
    final id = 'dog-${_nextId++}';
    _dogs.add(dog.copyWith(id: id));
    _notify();
    return id;
  }

  @override
  Future<void> updateDog(Dog dog) async {
    final i = _dogs.indexWhere((d) => d.id == dog.id);
    if (i >= 0) {
      _dogs[i] = dog;
    } else {
      _dogs.add(dog);
    }
    _notify();
  }

  @override
  Future<void> deleteDog(String dogId) async {
    _dogs.removeWhere((d) => d.id == dogId);
    _notify();
  }

  @override
  Future<String> uploadPhoto(String dogId, Uint8List bytes) async =>
      ''; // オフラインでは写真URLなし(プレビューはUI側のメモリ表示)
}

class InMemoryCareNoteRepository implements CareNoteRepository {
  final _controller = StreamController<List<CareNote>>.broadcast();
  final _notes = <CareNote>[];
  int _nextId = 1;

  void _notify() => _controller.add(List.unmodifiable(_notes));

  @override
  Stream<List<CareNote>> watchNotes(String dogId, {int limit = 200}) async* {
    List<CareNote> filter(List<CareNote> all) =>
        all.where((n) => n.dogId == dogId).take(limit).toList();
    yield filter(_notes);
    yield* _controller.stream.map(filter);
  }

  @override
  Future<String> add(CareNote note) async {
    final saved = note.copyWith(id: 'n-${_nextId++}');
    _notes.insert(0, saved);
    _notify();
    return saved.id;
  }

  @override
  Future<void> delete(String dogId, String noteId) async {
    _notes.removeWhere((n) => n.id == noteId);
    _notify();
  }
}

class InMemoryMeasurementRepository implements MeasurementRepository {
  final _controller = StreamController<Measurement?>.broadcast();
  final _items = <Measurement>[];
  int _nextId = 1;

  /// テスト・デバッグ用: 保存済み一覧(新しい順)
  List<Measurement> get saved => List.unmodifiable(_items);

  @override
  Future<String> save(String dogId, Measurement m) async {
    final saved = m.copyWith(id: 'm-${_nextId++}');
    _items.insert(0, saved);
    _controller.add(saved);
    return saved.id;
  }

  @override
  Future<List<Measurement>> fetchHistory(String dogId,
      {DateTime? before, int limit = 20}) async {
    var list = _items.where((m) => m.dogId == dogId).toList();
    if (before != null) {
      list = list.where((m) => m.startedAt.isBefore(before)).toList();
    }
    return list.take(limit).toList();
  }

  @override
  Stream<Measurement?> watchLatest(String dogId) async* {
    final existing = _items.where((m) => m.dogId == dogId).toList();
    yield existing.isEmpty ? null : existing.first;
    yield* _controller.stream.where((m) => m?.dogId == dogId);
  }
}
