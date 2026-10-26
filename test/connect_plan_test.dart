import 'package:flutter_test/flutter_test.dart';
import 'package:tanglex_chat/src/data/connect_plan.dart';

const _fullLink =
    'simplex:/contact#/?v=2-7&smp=smp%3A%2F%2Fkey%40smp11.simplex.im%2Fqueue';

Map<String, dynamic> _plan(Map<String, dynamic> connectionPlan) => {
  'result': {
    'type': 'connectionPlan',
    'user': {'userId': 1},
    'connLink': {'connFullLink': _fullLink, 'connShortLink': null},
    'planSimplexName': null,
    'otherSimplexName': null,
    'connectionPlan': connectionPlan,
  },
};

Map<String, dynamic> _contact(String type) => _plan({
  'type': 'contactAddress',
  'contactAddressPlan': {'type': type},
});

Map<String, dynamic> _invitation(String type) => _plan({
  'type': 'invitationLink',
  'invitationLinkPlan': {'type': type},
});

void main() {
  group('parseConnectPlanResponse', () {
    test('contact address plan resolves to a full link', () {
      final plan = parseConnectPlanResponse(_contact('ok'));
      expect(plan.action, ConnectPlanAction.proceed);
      expect(plan.canConnect, isTrue);
      expect(plan.fullLink, _fullLink);
    });

    test('invitation plan resolves to a full link', () {
      final plan = parseConnectPlanResponse(_invitation('ok'));
      expect(plan.canConnect, isTrue);
      expect(plan.fullLink, _fullLink);
    });

    test('own contact address is rejected with a specific message', () {
      final plan = parseConnectPlanResponse(_contact('ownLink'));
      expect(plan.canConnect, isFalse);
      expect(plan.message, contains('your own'));
    });

    test('already connecting is rejected', () {
      final plan = parseConnectPlanResponse(_contact('connectingProhibit'));
      expect(plan.canConnect, isFalse);
      expect(plan.message, contains('already connecting'));
    });

    test('known contact is rejected', () {
      final plan = parseConnectPlanResponse(_contact('known'));
      expect(plan.canConnect, isFalse);
      expect(plan.message, contains('already in your list'));
    });

    test('group link is rejected as unsupported', () {
      final plan = parseConnectPlanResponse(
        _plan({
          'type': 'groupLink',
          'groupLinkPlan': {'type': 'ok'},
        }),
      );
      expect(plan.canConnect, isFalse);
      expect(plan.message, contains('Group links'));
    });

    test('plan error surfaces the core error code', () {
      final plan = parseConnectPlanResponse(
        _plan({
          'type': 'error',
          'chatError': {
            'type': 'errorAgent',
            'agentError': {
              'type': 'AGENT',
              'agentErr': {'type': 'A_MESSAGE'},
            },
          },
        }),
      );
      expect(plan.canConnect, isFalse);
      expect(plan.message, 'This is not a valid SimpleX link.');
    });

    test('top-level API error is mapped', () {
      final plan = parseConnectPlanResponse({
        'error': {
          'type': 'errorAgent',
          'agentError': {
            'type': 'AGENT',
            'agentErr': {'type': 'A_MESSAGE'},
          },
        },
      });
      expect(plan.canConnect, isFalse);
      expect(plan.message, 'This is not a valid SimpleX link.');
    });

    test('missing full link fails instead of connecting blindly', () {
      final plan = parseConnectPlanResponse({
        'result': {
          'type': 'connectionPlan',
          'connLink': {'connFullLink': '', 'connShortLink': null},
          'connectionPlan': {
            'type': 'contactAddress',
            'contactAddressPlan': {'type': 'ok'},
          },
        },
      });
      expect(plan.canConnect, isFalse);
      expect(plan.message, contains('did not return a connection link'));
    });
  });

  test('a bare short-link key is detected', () {
    expect(
      looksLikeShortLinkKey('3IRXGsKfTvKf8Ca2_7BrUe1Oimt_ZCh6TIWrVTKgY68'),
      isTrue,
    );
    expect(looksLikeShortLinkKey('https://smp11.simplex.im/c#abc'), isFalse);
    expect(looksLikeShortLinkKey(_fullLink), isFalse);
  });

  test('unknown error codes still produce a readable message', () {
    expect(connectErrorMessage('CEInvalidConnReq'), contains('CEInvalidConnReq'));
    expect(connectErrorMessage(null), contains('Could not connect'));
  });
}
