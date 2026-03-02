class UserModel {
  final int id;
  final String phone;
  final String nickname;
  final String avatarUrl;
  final String memberType;
  final DateTime? memberExpireAt;
  final bool isNewUser;

  const UserModel({
    required this.id,
    required this.phone,
    required this.nickname,
    this.avatarUrl = '',
    this.memberType = 'free',
    this.memberExpireAt,
    this.isNewUser = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? 0,
      phone: json['phone'] ?? '',
      nickname: json['nickname'] ?? '',
      avatarUrl: json['avatar_url'] ?? '',
      memberType: json['member_type'] ?? 'free',
      memberExpireAt: json['member_expire_at'] != null
          ? DateTime.parse(json['member_expire_at'])
          : null,
      isNewUser: json['is_new_user'] ?? false,
    );
  }

  bool get isFree => memberType == 'free';
  bool get isPro => memberType == 'pro';
  bool get isFlagship => memberType == 'flagship';

  bool get isMemberValid {
    if (isFree) return false;
    if (memberExpireAt == null) return false;
    return memberExpireAt!.isAfter(DateTime.now());
  }
}
