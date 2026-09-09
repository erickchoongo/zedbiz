class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.phoneNumber,
    this.isPlatformAdmin = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    email: json['email'] as String,
    fullName: json['full_name'] as String,
    phoneNumber: json['phone_number'] as String?,
    isPlatformAdmin: json['is_platform_admin'] as bool? ?? false,
  );

  final String id;
  final String email;
  final String fullName;
  final String? phoneNumber;
  final bool isPlatformAdmin;
}
