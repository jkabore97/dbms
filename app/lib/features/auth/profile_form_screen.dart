import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/onboarding/onboarding_repository.dart';
import '../../core/phone/country_codes.dart';
import '../common/phone_field.dart';

/// Who somebody is, asked once, right after they make an account.
///
/// Both routes into the app go through this screen — the employee joining a
/// business and the manager asking for one — because both end up on a
/// payslip, a contract or a business registration, and none of those accept
/// "Awa" with no family name.
///
/// Two things it does that a plain form does not.
///
/// **The phone number is typed twice.** Not to satisfy the server, which
/// cannot tell two identical strings apart from one string sent twice, but to
/// catch the mistyped digit at the keyboard where it happens. A wrong number
/// here is not a small error: it is the number a manager sends the invitation
/// to, and the number the business calls when somebody does not come in.
///
/// **Nothing here grants anything.** Filling it in completely and pressing
/// save leaves somebody belonging to no business and seeing nothing. That is
/// stated on the screen, because a form this long implies a reward at the end
/// of it and the reward is one more step.
class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({
    super.key,
    required this.onboarding,
    this.title = 'Vos informations',
    this.nextLabel = 'Continuer',
    this.intro,
  });

  final OnboardingRepository onboarding;
  final String title;
  final String nextLabel;

  /// One line above the form saying what this is for. Different for the
  /// employee and the manager, because what happens next is different.
  final String? intro;

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  final _title = TextEditingController();
  final _phone = TextEditingController();
  final _phoneAgain = TextEditingController();

  CountryCode _country = defaultCountry;

  DateTime? _birth;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefill();
    for (final c in [_first, _middle, _last, _phone, _phoneAgain]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_first, _middle, _last, _title, _phone, _phoneAgain]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Somebody editing what they already told us should not retype it, and
  /// somebody who signed up by phone already has a number on file.
  Future<void> _prefill() async {
    final row = await widget.onboarding.myProfile();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (row == null) return;
      _first.text = (row['first_name'] as String?) ?? '';
      _middle.text = (row['middle_name'] as String?) ?? '';
      _last.text = (row['last_name'] as String?) ?? '';
      _title.text = (row['title'] as String?) ?? '';
      // What comes back is E.164. Showing it whole behind a picker that also
      // says "+226" would read as the code twice, so the stored number is
      // split back into the country it names and the part typed locally.
      final phone = (row['phone'] as String?) ?? '';
      final stored = countryOfNumber(phone);
      if (stored != null) _country = stored;
      final local = stored == null ? phone : stored.localPart(phone);
      _phone.text = local;
      // Pre-filled on both sides: it was already confirmed once, and asking
      // somebody to retype a number they did not just type is nagging.
      _phoneAgain.text = local;
      final dob = row['date_of_birth'];
      if (dob != null) _birth = DateTime.tryParse('$dob');
    });
  }

  String get _phoneText => _phone.text.trim();
  String get _phoneAgainText => _phoneAgain.text.trim();

  /// What the number becomes once the chosen country is applied. This screen
  /// used to save `_phoneText` exactly as typed while the sign-up screen saved
  /// E.164 — so the same person's number was stored two different ways
  /// depending on which screen they last used, and `claim_invitation()`
  /// matches `profiles.phone` literally. An invitation pinned to
  /// `+22670123456` simply did not match a profile reading `70 12 34 56`.
  String get _e164 => _country.toE164(_phoneText);

  String? get _phoneProblem {
    if (_phoneText.isEmpty) return null;
    if (_phoneAgainText.isEmpty) return null;
    // Compared normalised, so "70 12 34 56" and "70123456" are the agreement
    // they look like rather than a mismatch over a space.
    if (_e164 != _country.toE164(_phoneAgainText)) {
      return 'Les deux numéros ne sont pas identiques.';
    }
    return null;
  }

  bool get _ready =>
      !_saving &&
      _first.text.trim().isNotEmpty &&
      _last.text.trim().isNotEmpty &&
      _birth != null &&
      _phoneText.isNotEmpty &&
      _phoneAgainText.isNotEmpty &&
      _phoneProblem == null;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onboarding.saveProfile(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        middleName: _middle.text.trim(),
        dateOfBirth: _birth,
        title: _title.text.trim(),
        phone: _e164,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      // Opens on a plausible adult rather than today, which would otherwise
      // mean scrolling back thirty years every time.
      initialDate: _birth ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 14, now.month, now.day),
      helpText: 'Date de naissance',
    );
    if (picked != null) setState(() => _birth = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                if (widget.intro != null) ...[
                  Text(widget.intro!, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 20),
                ],

                TextField(
                  controller: _first,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Prénom',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _middle,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Deuxième prénom (facultatif)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _last,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Nom de famille',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickBirth,
                  icon: const Icon(Icons.cake_outlined),
                  label: Text(_birth == null
                      ? 'Date de naissance'
                      : DateFormat('d MMMM y', 'fr_FR').format(_birth!)),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Fonction (facultatif)',
                    helperText: 'Vendeuse, gérant, comptable…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                PhoneField(
                  controller: _phone,
                  country: _country,
                  onCountry: (c) => setState(() => _country = c),
                  labelText: 'Numéro de téléphone',
                  hintText: '70 12 34 56',
                  enabled: !_saving,
                ),
                const SizedBox(height: 12),
                PhoneField(
                  controller: _phoneAgain,
                  country: _country,
                  onCountry: (c) => setState(() => _country = c),
                  labelText: 'Confirmez le numéro',
                  enabled: !_saving,
                  errorText: _phoneProblem,
                  // Said plainly, because retyping something feels like
                  // pointless work unless the reason is on screen.
                  helperText: _phoneProblem == null
                      ? "C'est ce numéro que votre responsable utilisera."
                      : null,
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_error!),
                  ),
                ],

                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _ready ? _save : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.arrow_forward),
                  label: Text(widget.nextLabel),
                ),
                const SizedBox(height: 12),
                Text(
                  // A form this long implies a reward at the end of it. There
                  // is one more step, and saying so now is cheaper than a
                  // person wondering why nothing opened.
                  'Ces informations ne donnent accès à aucune entreprise. '
                  'Il faut ensuite un code, ou une demande approuvée.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
