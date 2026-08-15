import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/auth/pin_codec.dart';
import '../../core/errors.dart';

enum PinPurpose {
  /// First run after signing in: choose the code.
  create,

  /// The token has expired and there is no signal to refresh it.
  unlock,
}

/// The device code.
///
/// This exists because of one fact: an access token lasts about an hour, and
/// Ignace can be at the farm for three weeks. Without a local way back in, the
/// app would lock him out of records that are sitting on his own phone. The
/// code is checked entirely on the device — no network, by design.
///
/// The keypad is drawn rather than borrowed from the OS. It is always four
/// large targets wide, it never covers what it is for, and it does not change
/// shape between phones.
class PinScreen extends StatefulWidget {
  const PinScreen({
    super.key,
    required this.purpose,
    required this.identity,
    required this.onPinAccepted,
    this.onSignOut,
  });

  final PinPurpose purpose;
  final LocalIdentity identity;

  /// Given the accepted code. On [PinPurpose.create] the caller hashes and
  /// stores it; on unlock it has already been verified against the stored hash.
  final Future<void> Function(String pin) onPinAccepted;

  /// Forgotten code, or someone else's phone: start over with a real sign-in.
  final VoidCallback? onSignOut;

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  static const _pinLength = 4;

  String _entry = '';
  String? _firstEntry; // create flow: what they typed the first time
  String? _error;
  int _failures = 0;
  bool _busy = false;

  bool get _confirming => _firstEntry != null;

  String get _title {
    if (widget.purpose == PinPurpose.create) {
      return _confirming ? 'Confirmez le code' : 'Choisissez un code';
    }
    return 'Entrez votre code';
  }

  String get _subtitle {
    if (widget.purpose == PinPurpose.create) {
      return _confirming
          ? 'Entrez-le une seconde fois.'
          : "Ce code ouvre l'application quand vous n'avez pas de réseau.";
    }
    return widget.identity.label;
  }

  void _press(String digit) {
    if (_busy || _entry.length >= _pinLength) return;
    setState(() {
      _entry += digit;
      _error = null;
    });
    if (_entry.length == _pinLength) {
      // A beat so the fourth dot is visibly filled before the screen moves on.
      Future.delayed(const Duration(milliseconds: 120), _submit);
    }
  }

  void _backspace() {
    if (_busy || _entry.isEmpty) return;
    setState(() {
      _entry = _entry.substring(0, _entry.length - 1);
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!mounted || _entry.length != _pinLength) return;
    final pin = _entry;

    if (widget.purpose == PinPurpose.create) {
      if (!_confirming) {
        final problem = PinCodec.validate(pin);
        if (problem != null) {
          setState(() {
            _error = problem;
            _entry = '';
          });
          return;
        }
        setState(() {
          _firstEntry = pin;
          _entry = '';
        });
        return;
      }

      if (pin != _firstEntry) {
        setState(() {
          _error = 'Les deux codes ne correspondent pas. Recommencez.';
          _firstEntry = null;
          _entry = '';
        });
        return;
      }

      await _accept(pin);
      return;
    }

    // Unlock: the hash never leaves the device and neither does the code.
    final salt = widget.identity.pinSalt;
    final hash = widget.identity.pinHash;
    if (salt == null || hash == null) {
      setState(() => _error = 'Aucun code enregistré sur cet appareil.');
      return;
    }

    if (!PinCodec.verify(pin, salt: salt, hash: hash)) {
      setState(() {
        _failures++;
        _error = 'Code incorrect.';
        _entry = '';
      });
      return;
    }

    await _accept(pin);
  }

  Future<void> _accept(String pin) async {
    setState(() => _busy = true);
    try {
      await widget.onPinAccepted(pin);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = describeError(error);
          _entry = '';
          _firstEntry = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        // Scrollable rather than a bare Column: the keypad, the dots and the
        // sign-out line together are taller than a short window, and a fixed
        // Column simply clips whatever does not fit — which here is the way
        // out for somebody who cannot remember their code. Centred while
        // there is room, scrollable when there is not.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.purpose == PinPurpose.create
                              ? Icons.lock_outline
                              : Icons.lock_open_outlined,
                          size: 44,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 20),
                        Text(_title, style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        Text(
                          _subtitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _Dots(filled: _entry.length, total: _pinLength),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 40,
                          child: _error == null
                              ? null
                              : Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(color: theme.colorScheme.error),
                                ),
                        ),
                        _Keypad(onDigit: _press, onBackspace: _backspace),
                        const SizedBox(height: 16),
                        if (widget.onSignOut != null &&
                            widget.purpose == PinPurpose.unlock)
                          TextButton(
                            onPressed: _busy ? null : widget.onSignOut,
                            child: Text(
                              _failures >= 3
                                  ? 'Code oublié ? Se reconnecter par SMS'
                                  : 'Se reconnecter',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.filled, required this.total});

  final int filled;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final on = i < filled;
        return Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? theme.colorScheme.primary : Colors.transparent,
            border: Border.all(color: theme.colorScheme.primary, width: 2),
          ),
        );
      }),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBackspace});

  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '<'],
    ];

    return Column(
      children: [
        for (final row in rows)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final key in row)
                SizedBox(
                  width: 88,
                  height: 68,
                  child: key.isEmpty
                      ? const SizedBox.shrink()
                      : key == '<'
                          ? IconButton(
                              onPressed: onBackspace,
                              icon: const Icon(Icons.backspace_outlined),
                              iconSize: 26,
                              tooltip: 'Effacer',
                            )
                          : TextButton(
                              onPressed: () => onDigit(key),
                              child: Text(
                                key,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                ),
            ],
          ),
      ],
    );
  }
}
