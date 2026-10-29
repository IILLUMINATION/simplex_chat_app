/// One SimpleX user profile (an "account" in Telegram terms).
class AccountProfile {
  const AccountProfile({
    required this.userId,
    required this.displayName,
    this.fullName = '',
    this.shortDescr = '',
    this.image,
    this.localDisplayName = '',
    this.active = false,
  });

  final int userId;
  final String displayName;
  final String fullName;
  final String shortDescr;

  /// Data URL of the profile photo, exactly as the core stores it.
  final String? image;

  /// Internal name shown as the SimpleX address handle.
  final String localDisplayName;
  final bool active;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    final letters = parts.where((p) => p.isNotEmpty).take(2);
    final value = letters.map((p) => p.substring(0, 1)).join();
    return value.isEmpty ? '?' : value.toUpperCase();
  }

  factory AccountProfile.fromUserJson(
    Map<String, dynamic> user, {
    int? activeUserId,
  }) {
    Map<String, dynamic>? profile;
    final rawProfile = user['profile'];
    if (rawProfile is Map) profile = Map<String, dynamic>.from(rawProfile);
    final displayName = (profile?['displayName'] as String?)?.trim();
    final userId = user['userId'] as int? ?? 0;
    return AccountProfile(
      userId: userId,
      displayName: (displayName == null || displayName.isEmpty)
          ? 'SimpleX user'
          : displayName,
      fullName: profile?['fullName'] as String? ?? '',
      shortDescr: profile?['shortDescr'] as String? ?? '',
      image: profile?['image'] as String?,
      localDisplayName: user['localDisplayName'] as String? ?? '',
      active: activeUserId != null
          ? activeUserId == userId
          : user['activeUser'] == true,
    );
  }
}

/// All local profiles plus which one is active.
class AccountsState {
  const AccountsState({this.accounts = const [], this.activeUserId});

  final List<AccountProfile> accounts;
  final int? activeUserId;

  AccountProfile? get active {
    for (final account in accounts) {
      if (account.userId == activeUserId) return account;
    }
    return accounts.isEmpty ? null : accounts.first;
  }

  bool get isEmpty => accounts.isEmpty;
}
