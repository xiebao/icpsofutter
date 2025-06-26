class User {
  final String id;
  final String? userid;
  final String name;
  final String email;
  final String? phone;
  final String? avatarUrl;

  User({
    this.id = '0',
    this.name = '未登录',
    this.email = '',
    this.userid = '0',
    this.phone = '0',
    this.avatarUrl = '',
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '0',
      name: json['name'] ?? '未登录',
      email: json['email'] ?? '',
      userid: json['userid'] ?? '0',
      phone: json['phone'] ?? '0',
      avatarUrl: json['avatarUrl'],
    );
  }
}
