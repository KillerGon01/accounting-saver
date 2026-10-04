class AppUser {
  const AppUser({required this.uid, required this.email, this.displayName});

  final String uid;
  final String? email;
  final String? displayName;
}
