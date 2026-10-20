/// The signed-in person, as the accounts API describes them.
class AuthUser {
  final int id;
  final String email;
  final String name;

  const AuthUser({required this.id, required this.email, this.name = ''});

  /// What to call them: their name, else the part of the email before the @.
  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as int,
    email: json['email'] as String,
    name: (json['name'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'name': name};
}
