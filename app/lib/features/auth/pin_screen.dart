import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/mara_mark.dart';
import '../../l10n/strings.dart';

import '../../core/auth/models.dart';
import '../../core/auth/pin_codec.dart';
import '../../core/errors.dart';
import 'package:kaj_app/core/l10n/tr.dart';

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
    this.onBiometric,
  });

  /// Unlock with a fingerprint instead (Compte › Sécurité). Null when off,
  /// unavailable, or when choosing a code. True from the system means in;
  /// anything else leaves the keypad, which always works.
  final Future<bool> Function()? onBiometric;

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

  bool get _canBiometric =>
      widget.onBiometric != null && widget.purpose == PinPurpose.unlock;

  @override
  void initState() {
    super.initState();
    // Offered at once, as the phone's own lock screen does; dismissing it
    // leaves the keypad.
    if (_canBiometric) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
    }
  }

  Future<void> _biometric() async {
    final ask = widget.onBiometric;
    if (ask == null || _busy || !mounted) return;
    if (await ask() && mounted) await _accept('');
  }

  String get _title {
    if (widget.purpose == PinPurpose.create) {
      return _confirming
          ? Strings.of(context).pinConfirm
          : Strings.of(context).pinChoose;
    }
    return Strings.of(context).pinEnter;
  }

  String get _subtitle {
    if (widget.purpose == PinPurpose.create) {
      return _confirming
          ? Strings.of(context).pinConfirmSubtitle
          : Strings.of(context).pinChooseSubtitle;
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
          _error = Strings.of(context).pinMismatch;
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
      setState(() => _error = Strings.of(context).pinNoneStored);
      return;
    }

    if (!PinCodec.verify(pin, salt: salt, hash: hash)) {
      setState(() {
        _failures++;
        _error = Strings.of(context).pinWrong;
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
        child: LayoutBuilder(builder: (context, constraints) {
          // The keypad is sized to the height there is (UI audit AU-2): on
          // an iPhone SE at 1.3 the full header and 68 px keys put 7, 8, 9,
          // 0 and « Se reconnecter » below the fold, behind a scroll
          // nothing announced. A short screen gets a smaller mark, tighter
          // gaps, the title on one line, and keys between 44 and 68 px —
          // so the whole pad and the way out are on screen at once.
          final s = MediaQuery.textScalerOf(context).scale(1);
          final compact = constraints.maxHeight < 640;
          final header = compact
              ? 40 + 8 + 32 * s + 4 + 40 * s + 12 + 18 + 8 + 24
              : 64 + 20 + 32 * s + 8 + 40 * s + 32 + 18 + 16 + 40;
          final way = widget.onSignOut != null && widget.purpose == PinPurpose.unlock
              ? (compact ? 8 : 16) + 48 * math.max(1.0, s)
              : 0.0;
          final keyHeight =
              ((constraints.maxHeight - header - way - 8) / 4).clamp(44.0, 68.0);
          return SingleChildScrollView(
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
                        MaraMark(size: compact ? 40 : 64),
                        SizedBox(height: compact ? 8 : 20),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(_title,
                              key: const Key('pin-title'),
                              maxLines: 1,
                              style: theme.textTheme.headlineSmall),
                        ),
                        SizedBox(height: compact ? 4 : 8),
                        Text(
                          _subtitle,
                          textAlign: TextAlign.center,
                          maxLines: compact ? 2 : null,
                          overflow: compact ? TextOverflow.ellipsis : null,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: compact ? 12 : 32),
                        _Dots(filled: _entry.length, total: _pinLength),
                        SizedBox(height: compact ? 8 : 16),
                        SizedBox(
                          height: compact ? 24 : 40,
                          child: _error == null
                              ? null
                              : FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: theme.colorScheme.error),
                                  ),
                                ),
                        ),
                        _Keypad(
                          keyHeight: keyHeight,
                          onDigit: _press,
                          onBackspace: _backspace,
                          onBiometric: _canBiometric ? _biometric : null,
                        ),
                        SizedBox(height: compact ? 8 : 16),
                        if (widget.onSignOut != null &&
                            widget.purpose == PinPurpose.unlock)
                          TextButton(
                            key: const Key('pin-sign-out'),
                            onPressed: _busy ? null : widget.onSignOut,
                            child: Text(
                              _failures >= 3
                                  ? Strings.of(context).pinForgot
                                  : Strings.of(context).pinReconnect,
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
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
  const _Keypad({
    this.keyHeight = 68,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
  });

  /// Each key's height: 68 where there is room, less on a short screen.
  final double keyHeight;
  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;

  /// The fingerprint, in the keypad's empty corner.
  final VoidCallback? onBiometric;

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
                  height: keyHeight,
                  child: key.isEmpty
                      ? (onBiometric == null
                          ? const SizedBox.shrink()
                          : IconButton(
                              onPressed: onBiometric,
                              icon: const Icon(Icons.fingerprint),
                              iconSize: 30,
                              tooltip: context.tr('Empreinte digitale'),
                            ))
                      : key == '<'
                          ? IconButton(
                              onPressed: onBackspace,
                              icon: const Icon(Icons.backspace_outlined),
                              iconSize: 26,
                              tooltip: context.tr('Effacer'),
                            )
                          : TextButton(
                              onPressed: () => onDigit(key),
                              style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  key,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w500,
                                  ),
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
