import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

/// User model
@freezed
class User with _$User {
  const factory User({
    required String id,
    required String email,
    String? username,
    String? avatarUrl,
    required UserSubscription subscription,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}

/// User subscription info
@freezed
class UserSubscription with _$UserSubscription {
  const factory UserSubscription({
    required String planName,
    required DateTime expireAt,
    required int trafficTotal, // Total traffic in bytes
    required int trafficUsed, // Used traffic in bytes
    required int trafficRemaining, // Remaining traffic in bytes
    String? subscriptionUrl,
    DateTime? lastUpdated,
    @Default(false) bool isExpired,
    @Default(false) bool isLimited,
  }) = _UserSubscription;

  factory UserSubscription.fromJson(Map<String, dynamic> json) =>
      _$UserSubscriptionFromJson(json);
}

/// User session
@freezed
class UserSession with _$UserSession {
  const factory UserSession({
    required String token,
    required String refreshToken,
    required DateTime expiresAt,
    required User user,
  }) = _UserSession;

  factory UserSession.fromJson(Map<String, dynamic> json) =>
      _$UserSessionFromJson(json);
}
