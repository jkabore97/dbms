import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/whatsapp_phone.dart';
import '../../core/l10n/tr.dart';
import '../../core/phone/country_codes.dart';
import '../../core/theme/mara_mark.dart';
import '../common/phone_field.dart';
import 'shop_style.dart';
import '../../core/notify/bell_room.dart';

/// « Votre numéro WhatsApp » (F2): before the first order, once the
/// platform asks for it (109's order_phone_verified), a shopper with no
/// proved number gives theirs and types back the code WhatsApp brought.
/// The country first (Burkina Faso unless chosen), the number checked for
/// its country's length (032/103), « Recevoir le code sur WhatsApp », six
/// digits, « Renvoyer » after a minute. Pops with the proved number, or
/// null when the shopper leaves.
class WhatsAppVerifyScreen extends StatefulWidget {
  const WhatsAppVerifyScreen({
    super.key,
    required this.phone,
    this.resendAfter = const Duration(seconds: 60),
    this.intro,
  });

  final WhatsAppPhone phone;

  /// Why the number is asked, above the field; null: before an order. The
  /// creation of a business asks it too (111).
  final String? intro;

  /// How long before « Renvoyer le code » (Supabase's own minimum between
  /// two codes is a minute).
  final Duration resendAfter;

  static Route<String> route(WhatsAppPhone phone, {String? intro}) => MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => WhatsAppVerifyScreen(phone: phone, intro: intro),
      );

  @override
  State<WhatsAppVerifyScreen> createState() => _WhatsAppVerifyScreenState();
}

class _WhatsAppVerifyScreenState extends State<WhatsAppVerifyScreen> {
  final _number = TextEditingController();
  final _code = TextEditingController();
  CountryCode _country = defaultCountry;

  /// The number the code was sent to; null until then.
  String? _sentTo;
  bool _busy = false;
  String? _error;

  Timer? _tick;
  int _wait = 0;

  @override
  void dispose() {
    _tick?.cancel();
    _number.dispose();
    _code.dispose();
    super.dispose();
  }

  String? get _lengthProblem =>
      _number.text.trim().isEmpty ? null : _country.lengthProblem(_number.text);

  bool get _numberReady => _number.text.trim().isNotEmpty && _lengthProblem == null;

  void _startWait() {
    _tick?.cancel();
    setState(() => _wait = widget.resendAfter.inSeconds);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait = _wait > 0 ? _wait - 1 : 0);
      if (_wait == 0) t.cancel();
    });
  }

  Future<void> _send() async {
    if (!_numberReady || _busy) return;
    final e164 = _country.toE164(_number.text);
    final language = context.trLanguage;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.phone.sendCode(e164);
      if (!mounted) return;
      setState(() {
        _sentTo = e164;
        _code.clear();
      });
      _startWait();
    } catch (e) {
      if (mounted) setState(() => _error = whatsAppProblem(language, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final to = _sentTo;
    final code = _code.text.trim();
    if (to == null || code.length != 6 || _busy) return;
    final language = context.trLanguage;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.phone.confirm(to, code);
      if (!mounted) return;
      Navigator.of(context).pop(to);
    } catch (e) {
      if (mounted) {
        setState(() => _error = whatsAppProblem(language, e, confirming: true));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeNumber() {
    _tick?.cancel();
    setState(() {
      _sentTo = null;
      _wait = 0;
      _error = null;
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ShopStyle.theme(context),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            actions: const [bellRoom],
            leading: IconButton(
              tooltip: context.tr('Fermer'),
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(context.tr('Votre numéro WhatsApp')),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 44, color: maraGreen),
                    const SizedBox(height: 12),
                    Text(
                      widget.intro ??
                          context.tr('Avant votre première commande, Mara vérifie votre numéro : la boutique pourra vous joindre.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, color: ShopStyle.ink, height: 1.35),
                    ),
                    const SizedBox(height: 24),
                    if (_sentTo == null) ..._numberStep(context) else ..._codeStep(context),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        key: const Key('whatsapp-error'),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBE9E7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline, color: Color(0xFFB3261E), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Color(0xFF8C1D18), fontSize: 15),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _numberStep(BuildContext context) => [
        PhoneField(
          key: const Key('whatsapp-number'),
          controller: _number,
          country: _country,
          onCountry: (c) => setState(() => _country = c),
          labelText: context.tr('Votre numéro WhatsApp'),
          hintText: '70 12 34 56',
          enabled: !_busy,
          large: true,
          autofillHints: const [AutofillHints.telephoneNumber],
          errorText: _lengthProblem,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            key: const Key('whatsapp-send'),
            style: FilledButton.styleFrom(backgroundColor: maraGreen, foregroundColor: Colors.white),
            onPressed: _numberReady && !_busy ? _send : null,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.chat_outlined),
            label: Text(context.tr('Recevoir le code sur WhatsApp')),
          ),
        ),
      ];

  List<Widget> _codeStep(BuildContext context) => [
        Text(
          context.tr('Code envoyé sur WhatsApp au {phone}.', {'phone': _sentTo}),
          key: const Key('whatsapp-sent'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: ShopStyle.mist),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('whatsapp-code'),
          controller: _code,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 30, letterSpacing: 10, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            labelText: context.tr('Code à 6 chiffres'),
            counterText: '',
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) {
            setState(() {});
            // The sixth digit is the tap: no button to hunt for.
            if (v.trim().length == 6) _confirm();
          },
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          child: FilledButton(
            key: const Key('whatsapp-confirm'),
            onPressed: _code.text.trim().length == 6 && !_busy ? _confirm : null,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: ShopStyle.paper),
                  )
                : Text(context.tr('Vérifier')),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            TextButton(
              key: const Key('whatsapp-resend'),
              onPressed: _wait == 0 && !_busy ? _send : null,
              child: Text(_wait == 0
                  ? context.tr('Renvoyer le code')
                  : context.tr('Renvoyer le code dans {s} s', {'s': _wait})),
            ),
            TextButton(
              key: const Key('whatsapp-change'),
              onPressed: _busy ? null : _changeNumber,
              child: Text(context.tr('Changer de numéro')),
            ),
          ],
        ),
      ];
}
