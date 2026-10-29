import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/account_models.dart';
import 'package:tanglex_chat/src/service/tanglex_service.dart';

void main() {
  test('the users list unwraps the per-user envelope', () {
    final users = parseUsersListResponse({
      'result': {
        'type': 'usersList',
        'users': [
          {
            'user': {
              'userId': 1,
              'localDisplayName': 'alice',
              'profile': {'displayName': 'Alice', 'fullName': 'A. Lice'},
              'activeUser': true,
            },
            'unreadCount': 3,
          },
        ],
      },
    });

    expect(users, hasLength(1));
    expect(users.single['userId'], 1);

    final account = AccountProfile.fromUserJson(users.single);
    expect(account.userId, 1);
    expect(account.displayName, 'Alice');
    expect(account.fullName, 'A. Lice');
    expect(account.active, isTrue);
  });

  test('a non-users-list response yields no profiles', () {
    expect(
      parseUsersListResponse({
        'result': {'type': 'activeUser'},
      }),
      isEmpty,
    );
  });
}
