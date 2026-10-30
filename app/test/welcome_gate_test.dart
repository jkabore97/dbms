import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/features/auth/welcome_gate.dart';

/// The welcome gate (batch 152): where it stands and for whom.
void main() {
  test('a stranger on the street sees the gate', () {
    expect(welcomeGateShows(SessionPhase.signedOut, '/'), isTrue);
    expect(welcomeGateShows(SessionPhase.signedOut, '/vitrines'), isTrue);
    expect(welcomeGateShows(SessionPhase.signedOut, '/vitrines/masquees'), isTrue);
  });

  test("a shop's own vitrine, the sign-in page and the legal pages stay open", () {
    expect(welcomeGateShows(SessionPhase.signedOut, '/s/chez-awa'), isFalse);
    expect(welcomeGateShows(SessionPhase.signedOut, '/connexion'), isFalse);
    expect(welcomeGateShows(SessionPhase.signedOut, '/conditions'), isFalse);
    expect(welcomeGateShows(SessionPhase.signedOut, '/confidentialite'), isFalse);
    expect(welcomeGateShows(SessionPhase.signedOut, '/devenir-livreur'), isFalse);
    expect(welcomeGateShows(SessionPhase.signedOut, '/aide'), isFalse);
  });

  test('nobody signed in, or still being read at start, sees it', () {
    for (final phase in SessionPhase.values) {
      if (phase == SessionPhase.signedOut) continue;
      expect(welcomeGateShows(phase, '/vitrines'), isFalse, reason: '$phase');
    }
  });
}
