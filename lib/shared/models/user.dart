/// User model
class User {
  final String id;
  final String email;
  final String? username;
  final String? avatarUrl;
  final UserSubscription subscription;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  const User({
    required this.id,
    required this.email,
    this.username,
    this.avatarUrl,
    required this.subscription,
    this.createdAt,
    this.lastLoginAt,
  });

  User copyWith({
    String? id,
    String? email,
    String? username,
    String? avatarUrl,
    UserSubscription? subscription,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      subscription: subscription ?? this.subscription,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'username': username,
    'avatarUrl': avatarUrl,
    'subscription': subscription.toJson(),
    'createdAt': createdAt?.toIso8601String(),
    'lastLoginAt': lastLoginAt?.toIso8601String(),
  };

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    email: json['email'] as String,
    username: json['username'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    subscription: UserSubscription.fromJson(
      json['subscription'] as Map<String, dynamic>,
    ),
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : null,
    lastLoginAt: json['lastLoginAt'] != null
        ? DateTime.parse(json['lastLoginAt'] as String)
        : null,
  );
}

/// User subscription info
class UserSubscription {
  final String planName;
  final DateTime expireAt;
  final int trafficTotal;
  final int trafficUsed;
  final int trafficRemaining;
  final String? subscriptionUrl;
  final DateTime? lastUpdated;
  final bool isExpired;
  final bool isLimited;

  const UserSubscription({
    required this.planName,
    required this.expireAt,
    required this.trafficTotal,
    required this.trafficUsed,
    required this.trafficRemaining,
    this.subscriptionUrl,
    this.lastUpdated,
    this.isExpired = false,
    this.isLimited = false,
  });

  UserSubscription copyWith({
    String? planName,
    DateTime? expireAt,
    int? trafficTotal,
    int? trafficUsed,
    int? trafficRemaining,
    String? subscriptionUrl,
    DateTime? lastUpdated,
    bool? isExpired,
    bool? isLimited,
  }) {
    return UserSubscription(
      planName: planName ?? this.planName,
      expireAt: expireAt ?? this.expireAt,
      trafficTotal: trafficTotal ?? this.trafficTotal,
      trafficUsed: trafficUsed ?? this.trafficUsed,
      trafficRemaining: trafficRemaining ?? this.trafficRemaining,
      subscriptionUrl: subscriptionUrl ?? this.subscriptionUrl,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isExpired: isExpired ?? this.isExpired,
      isLimited: isLimited ?? this.isLimited,
    );
  }

  Map<String, dynamic> toJson() => {
    'planName': planName,
    'expireAt': expireAt.toIso8601String(),
    'trafficTotal': trafficTotal,
    'trafficUsed': trafficUsed,
    'trafficRemaining': trafficRemaining,
    'subscriptionUrl': subscriptionUrl,
    'lastUpdated': lastUpdated?.toIso8601String(),
    'isExpired': isExpired,
    'isLimited': isLimited,
  };

  factory UserSubscription.fromJson(Map<String, dynamic> json) =>
      UserSubscription(
        planName: json['planName'] as String,
        expireAt: DateTime.parse(json['expireAt'] as String),
        trafficTotal: json['trafficTotal'] as int,
        trafficUsed: json['trafficUsed'] as int,
        trafficRemaining: json['trafficRemaining'] as int,
        subscriptionUrl: json['subscriptionUrl'] as String?,
        lastUpdated: json['lastUpdated'] != null
            ? DateTime.parse(json['lastUpdated'] as String)
            : null,
        isExpired: json['isExpired'] as bool? ?? false,
        isLimited: json['isLimited'] as bool? ?? false,
      );
}

/// User session
class UserSession {
  final String token;
  final String refreshToken;
  final DateTime expiresAt;
  final User user;

  const UserSession({
    required this.token,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  Map<String, dynamic> toJson() => {
    'token': token,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
    'user': user.toJson(),
  };

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
    token: json['token'] as String,
    refreshToken: json['refreshToken'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    user: User.fromJson(json['user'] as Map<String, dynamic>),
  );
}
