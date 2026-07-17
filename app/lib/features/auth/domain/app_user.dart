/// 認証ユーザー(domainエンティティ)。FirebaseAuthのUserをアプリ内表現に変換。
class AppUser {
  const AppUser({
    required this.uid,
    this.email,
    this.displayName,
    this.isAnonymous = false,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final bool isAnonymous;
}
