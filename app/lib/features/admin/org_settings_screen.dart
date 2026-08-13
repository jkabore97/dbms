import 'package:flutter/material.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/auth/auth_repository.dart';

/// The business's own details.
///
/// Only two fields are editable, and the ones that are missing matter more
/// than the ones that are here:
///
///  * `slug` is a live subdomain. Changing it breaks every link anyone has.
///  * `profile` decides which home screen every member of the org opens on.
///    Changing it from a settings form would move a whole congregation to a
///    farm screen because somebody was curious.
///
/// Both are shown, read-only, so an admin can see what they are and quote them
/// when asking for a change.
class OrgSettingsScreen extends StatefulWidget {
  const OrgSettingsScreen({
    super.key,
    required this.admin,
    required this.orgId,
    this.onSaved,
  });

  final AdminRepository admin;
  final String orgId;

  /// Lets whoever opened this refresh the org list — the name shown in the app
  /// bar and the picker comes from `my_orgs()`, not from this screen.
  final VoidCallback? onSaved;

  @override
  State<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends State<OrgSettingsScreen> {
  final _nameController = TextEditingController();

  String _currency = 'XOF';
  String _slug = '';
  String _profile = '';

  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _currencies = ['XOF', 'XAF', 'EUR', 'USD', 'GHS', 'NGN'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final org = await widget.admin.fetchOrg(widget.orgId);
      if (!mounted) return;
      setState(() {
        _nameController.text = (org['name'] as String?) ?? '';
        final currency = (org['default_currency'] as String?) ?? 'XOF';
        _currency = _currencies.contains(currency) ? currency : 'XOF';
        _slug = (org['slug'] as String?) ?? '';
        _profile = (org['profile'] as String?) ?? 'generic';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = "Le nom de l'activité ne peut pas être vide.");
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.admin.updateOrg(
        orgId: widget.orgId,
        name: name,
        currency: _currency,
      );
      widget.onSaved?.call();
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enregistré')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Paramètres de l'activité")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Nom', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 24),
                Text('Monnaie', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final c in _currencies)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged:
                      _saving ? null : (v) => setState(() => _currency = v!),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Enregistrer',
                            style: TextStyle(fontSize: 17),
                          ),
                  ),
                ),

                const SizedBox(height: 40),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  'Non modifiable ici',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  "L'adresse web et le type d'activité changent ce que voient "
                  'tous les membres. Contactez Kaj-consulting pour les '
                  'modifier.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _ReadOnlyRow(label: 'Adresse web', value: '$_slug.kajapp.com'),
                _ReadOnlyRow(label: "Type d'activité", value: _profile),
              ],
            ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
