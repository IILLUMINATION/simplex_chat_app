/// Outcome of a "New chat → connect by link" attempt.
class ConnectOutcome {
  const ConnectOutcome.success()
      : ok = true,
        message = null;

  const ConnectOutcome.error(this.message) : ok = false;

  final bool ok;
  final String? message;
}

enum ConnectPlanAction {
  proceed,
  ownLink,
  alreadyKnown,
  alreadyConnecting,
  groupLink,
  failed,
}

/// Parsed result of the core's `/_connect plan` command.
///
/// Mirrors `ConnectionPlan` from the SimpleX API: the plan resolves short
/// links and names to a full link, and tells us whether connecting is safe.
class ConnectPlan {
  const ConnectPlan(this.action, {this.fullLink, this.message});

  const ConnectPlan.failed(this.message)
      : action = ConnectPlanAction.failed,
        fullLink = null;

  final ConnectPlanAction action;
  final String? fullLink;
  final String? message;

  bool get canConnect =>
      action == ConnectPlanAction.proceed && fullLink != null;
}

const String shortLinkKeyHint =
    'That is only the key from a short link. Paste the full link, '
    'e.g. https://smp.example.com/c#<key> or simplex:/contact#…';

final RegExp _shortLinkKey = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// A bare 32-byte base64url key (the fragment of a short link) is not a link:
/// the core has no server to resolve it against.
bool looksLikeShortLinkKey(String value) => _shortLinkKey.hasMatch(value);

ConnectPlan parseConnectPlanResponse(Map<String, dynamic> json) {
  final error = json['error'];
  if (error != null) {
    return ConnectPlan.failed(connectErrorMessage(coreErrorCode(error)));
  }
  final result = json['result'];
  if (result is! Map) {
    return const ConnectPlan.failed('Unexpected response from the core.');
  }
  final resultMap = Map<String, dynamic>.from(result);
  final fullLink = findConnFullLink(resultMap['connLink']);
  final rawPlan = resultMap['connectionPlan'];
  if (rawPlan is! Map) {
    return const ConnectPlan.failed('Unexpected response from the core.');
  }
  final plan = Map<String, dynamic>.from(rawPlan);
  final planType = plan['type'];

  if (planType == 'contactAddress') {
    final sub = _subPlan(plan['contactAddressPlan']);
    switch (sub?['type']) {
      case 'ok':
        return _proceed(fullLink);
      case 'ownLink':
        return const ConnectPlan.failed(
          'This is your own SimpleX address.',
        );
      case 'connectingConfirmReconnect':
      case 'connectingProhibit':
        return const ConnectPlan.failed(
          'You are already connecting via this link.',
        );
      case 'known':
      case 'contactViaAddress':
        return const ConnectPlan.failed(
          'This contact is already in your list.',
        );
    }
    return const ConnectPlan.failed('Unexpected contact plan from the core.');
  }

  if (planType == 'invitationLink') {
    final sub = _subPlan(plan['invitationLinkPlan']);
    switch (sub?['type']) {
      case 'ok':
        return _proceed(fullLink);
      case 'ownLink':
        return const ConnectPlan.failed(
          'This is your own one-time invitation link.',
        );
      case 'connecting':
        return const ConnectPlan.failed(
          'You are already connecting via this link.',
        );
      case 'known':
        return const ConnectPlan.failed(
          'This contact is already in your list.',
        );
    }
    return const ConnectPlan.failed(
      'Unexpected invitation plan from the core.',
    );
  }

  if (planType == 'groupLink') {
    return const ConnectPlan.failed(
      'Group links are not supported yet.',
    );
  }

  if (planType == 'error') {
    return ConnectPlan.failed(connectErrorMessage(coreErrorCode(plan)));
  }

  return const ConnectPlan.failed('Unexpected response from the core.');
}

ConnectPlan _proceed(String? fullLink) => fullLink == null
    ? const ConnectPlan.failed('The core did not return a connection link.')
    : ConnectPlan(
        ConnectPlanAction.proceed,
        fullLink: fullLink,
      );

Map<String, dynamic>? _subPlan(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

/// `CRConnectionPlan.connLink` is a `CreatedConnLink`:
/// `{"connFullLink": "...", "connShortLink": null}`.
String? findConnFullLink(Object? node, [int depth = 0]) {
  if (depth > 4) return null;
  if (node is Map) {
    final full = node['connFullLink'];
    if (full is String && full.isNotEmpty) return full;
    for (final value in node.values) {
      final found = findConnFullLink(value, depth + 1);
      if (found != null) return found;
    }
  } else if (node is List) {
    for (final value in node) {
      final found = findConnFullLink(value, depth + 1);
      if (found != null) return found;
    }
  }
  return null;
}

/// Extracts the innermost error code from SimpleX `ChatError`/API error JSON.
String? coreErrorCode(Object? error) {
  if (error is! Map) return null;
  final map = Map<String, dynamic>.from(error);
  final errorType = map['errorType'];
  if (errorType is Map) {
    final type = Map<String, dynamic>.from(errorType);
    return type['type'] as String? ?? type['message'] as String?;
  }
  final storeError = map['storeError'];
  if (storeError is Map) {
    return storeError['type'] as String?;
  }
  final agentError = map['agentError'];
  if (agentError is Map) {
    final agent = Map<String, dynamic>.from(agentError);
    final agentErr = agent['agentErr'];
    if (agentErr is Map) {
      return agentErr['type'] as String?;
    }
    return agent['type'] as String?;
  }
  final chatError = map['chatError'];
  if (chatError is Map) return coreErrorCode(chatError);
  return map['type'] as String?;
}

String connectErrorMessage(String? code) {
  return switch (code) {
    'A_MESSAGE' => 'This is not a valid SimpleX link.',
    'invalidConnReq' => 'This connection link is not valid.',
    'notResolvedLocally' => 'This SimpleX name could not be found.',
    null => 'Could not connect. Check the link and try again.',
    _ => 'Could not connect ($code).',
  };
}
