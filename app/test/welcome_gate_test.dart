import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/features/auth/welcome_gate.dart';

/// The welcome gate (batch 152): where it stands and for whom.
void main() {
  test('a stranger meets the gate on every link: the street, a shared vitrine, the rest', () {
    expect(welcomeGateShows(SessionPhase.signedOut, '/'), isTrue);
    expect(welcomeGateShows(SessionPhase.signedOut, '/vitrines'), isTrue);
    expect(welcomeGateShows(SessionPhase.signedOut, '/vitrines/masquees'), isTrue);
    expect(welcomeGateShows(SessionPhase.signedOut, '/s/chez-awa'), isTrue);
    expect(welcomeGateShows(SessionPhase.signedOut, '/devenir-livreur'), isTrue);
    expect(welcomeGateShows(SessionPhase.signedOut, '/aide'), isTrue);
    expect(welcomeGateShows(SessionPhase.signedOut, '/rejoindre'), isTrue);
  });

  test('the way in, the two texts the sheet links to and the payment return stay open', () {
    expect(welcomeGateShows(SessionPhase.signedOut, '/connexion'), isFalse);
    expect(welcomeGateShows(SessionPhase.signedOut, '/conditions'), isFalse);
    expect(welcomeGateShows(SessionPhase.signedOut, '/confidentialite'), isFalse);
    expect(welcomeGateShows(SessionPhase.signedOut, '/paiement/abc'), isFalse);
  });

  test('the tests-only switch takes it down', () {
    WelcomeGate.enabled = false;
    try {
      expect(welcomeGateShows(SessionPhase.signedOut, '/'), isFalse);
    } finally {
      WelcomeGate.enabled = true;
    }
  });

  test('nobody signed in, or still being read at start, sees it', () {
    for (final phase in SessionPhase.values) {
      if (phase == SessionPhase.signedOut) continue;
      expect(welcomeGateShows(phase, '/vitrines'), isFalse, reason: '$phase');
    }
  });
}
