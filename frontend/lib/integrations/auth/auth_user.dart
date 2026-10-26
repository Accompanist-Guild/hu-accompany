/// The signed-in person, as the accounts API describes them.
class AuthUser {
  final int id;
  final String email;
  final String name;

  /// "admin" and/or "contributor" (backend guidelines/permissions.py). Only
  /// decides whether the Guides tab is shown: the server checks again on
  /// every change.
  final List<String> roles;

  const AuthUser({
    required this.id,
    required this.email,
    this.name = '',
    this.roles = const [],
  });

  /// What to call them: their name, else the part of the email before the @.
  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  /// May write guidelines: an admin or a verified contributor.
  bool get canAuthorGuidelines =>
      roles.contains('admin') || roles.contains('contributor');

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as int,
    email: json['email'] as String,
    name: (json['name'] as String?) ?? '',
    roles: [for (final r in json['roles'] as List<dynamic>? ?? const []) '$r'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'roles': roles,
  };
}
