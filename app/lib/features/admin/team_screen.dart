import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/admin/models.dart'
    show Member, accountRankOf, accountRoleRank, roleLabel;
import '../../core/admin/team.dart';
import '../../core/auth/models.dart';
import '../../core/cauris/feature_states.dart';
import '../../core/errors.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/onboarding/onboarding_repository.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/theme/mara_mark.dart';
import '../account/pro_sheet.dart';
import '../cauris/unlock_sheet.dart';
import 'member_edit_sheet.dart';
import 'team_invite_flow.dart';

/// « Équipe » (100): the one place for the business's people — who is in,
/// adding somebody (the invitation, 017), replacing or removing them, the
/// invitations still out, and what each person is paid. Since 101 it is
/// also where a person's information, responsibility and sessions are
/// managed — the old « Personnes » screen is folded in here.
///
/// On Basic the owner has one person free once the first setup is done (an
/// association at once); more is Mara Pro or the team unlocked with cauris.
/// The card at the top says which, before anybody is invited: the server
/// refuses the same at the invitation and at the door. Recording a salary
/// is free; paying it goes through the payroll, which stays Pro. The same
/// screen for a shop, a farm and an association.
class TeamScreen extends StatefulWidget {
  const TeamScreen({
    super.key,
    required this.org,
    required this.admin,
    required this.onboarding,
    this.embedded = false,
  });

  final OrgSummary org;
  final AdminRepository admin;
  final OnboardingRepository onboarding;

  /// Drawn inside another page's tab — the command center's fiche (106) —
  /// which has its own top bar: none here.
  final bool embedded;

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  TeamOverview? _team;

  /// Each person's grants with their own information (fetchMembers), by
  /// account — the responsibility to change, the profile to read and edit.
  /// Best-effort: without it the sheet keeps the salary and the removal.
  Map<String, List<Member>> _accounts = const {};

  /// Names for the scope a grant covers — a site, « Site · département » —
  /// so a grant reads « Boutique du marché » rather than an id. Best-effort.
  Map<String, String> _scopeNames = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final team = await widget.admin.teamOverview(widget.org.id);
      var accounts = _accounts;
      try {
        final rows = await widget.admin.fetchMembers(widget.org.id);
        accounts = {};
        for (final r in rows) {
          (accounts[r.userId] ??= []).add(r);
        }
      } catch (_) {}
      var names = _scopeNames;
      try {
        final structure = await widget.admin.fetchStructure(widget.org.id);
        names = {};
        for (final entity in structure) {
          names[entity.id] = entity.name;
          for (final dept in entity.departments) {
            names[dept.id] = '${entity.name} · ${dept.name}';
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _team = team;
        _accounts = accounts;
        _scopeNames = names;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  /// After a person comes or goes: this screen, and the seat the rest of
  /// the app reads (Compte's line, the lock).
  Future<void> _reloadAll() async {
    await AppScope.read(context)?.session.reloadFeatures(widget.org.id);
    if (mounted) await _load();
  }

  /// The seats as last read: the screen's own read, else the session's.
  TeamSeats? get _seats =>
      _team?.seats ?? AppScope.read(context)?.session.featuresFor(widget.org.id)?.team;

  Future<void> _add() async {
    final seats = _seats;
    if (seats != null && !seats.open) {
      await _unlock();
      return;
    }
    await _invite();
  }

  /// « Ajouter une personne », one question a screen (115).
  Future<void> _invite() async {
    await TeamInviteFlow.open(context,
        org: widget.org, onboarding: widget.onboarding, admin: widget.admin);
    if (mounted) await _reloadAll();
  }

  Future<void> _unlock() async {
    final scope = AppScope.read(context);
    await UnlockSheet.open(context, org: widget.org, feature: 'team_access');
    await scope?.session.reloadFeatures(widget.org.id);
    if (mounted) await _load();
  }

  /// Before the first setup: a shop, a farm or an association finishes it
  /// from its home (the walkthrough, 091 and 102); anything else from its
  /// settings.
  void _finishSetup() {
    const walked = {'retail', 'farm', 'association', 'church'};
    if (walked.contains(widget.org.profile)) {
      context.go(Routes.org(widget.org.id));
    } else {
      context.push(Routes.orgSettings(widget.org.id));
    }
  }

  int get _myRank => accountRankOf(widget.org.roles);

  /// Whether this person may be managed from here — their salary, their
  /// information, their responsibility, their sessions, their removal:
  /// never the owner nor oneself, and only somebody below the caller (045's
  /// ladder; the server holds the same).
  bool _canManage(TeamMember m) =>
      !m.isOwner && !m.isMe && _myRank > accountRankOf(m.roles);

  bool _canRemove(TeamMember m) => _canManage(m) && m.membershipIds.isNotEmpty;

  /// A salary is the owner's to read, and that of whoever outranks the
  /// person.
  bool _seesPay(TeamMember m) =>
      widget.org.roles.contains('owner') || _canManage(m);

  /// What each of the person's grants covers, as the old « Personnes »
  /// screen said it: « Toute l'activité », a site, « Site · département »,
  /// and « · totaux seulement » for a grant that sees the totals only. The
  /// role is named per grant only when there are several. Null while the
  /// grants are unknown.
  String? _scopeLine(TeamMember m) {
    final rows = _accounts[m.userId];
    if (rows == null || rows.isEmpty) return null;
    String label(Member g) {
      final named = _scopeNames[g.scopeId];
      final scope = named ??
          switch (g.scopeKind) {
            'org' => context.tr('Toute l\'activité'),
            'entity' => context.tr('Site'),
            'department' => context.tr('Département'),
            _ => g.scopeKind,
          };
      return [
        if (rows.length > 1) context.tr(roleLabel(g.role)),
        scope,
      ].join(' · ') +
          (g.visibility == 'summary' ? context.tr(' · totaux seulement') : '');
    }

    return rows.map(label).join('\n');
  }

  /// The grant whose responsibility is changed: the person's highest.
  Member? _primary(TeamMember m) {
    final rows = _accounts[m.userId];
    if (rows == null || rows.isEmpty) return null;
    return rows.reduce((a, b) =>
        accountRoleRank(b.role) > accountRoleRank(a.role) ? b : a);
  }

  Future<void> _member(TeamMember m) async {
    final theme = Theme.of(context);
    final removable = _canRemove(m);
    final manage = _canManage(m);
    final account = _primary(m);
    final canWorker = widget.admin.canManageAccounts;
    final roles = grantableRolesFor(widget.org.roles);
    final hasSessions = AppScope.read(context)?.securityApi != null;
    final locale = context.trLanguage == 'en' ? 'en' : 'fr_FR';
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      // Tall with every action: it scrolls on a small phone.
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(m.name, style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(context.tr(roleLabel(m.role)),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            // Their own information — read by whoever manages the team.
            if (account != null) ...[
              _info(sheet, context.tr('Téléphone'), account.phone ?? m.phone),
              _info(sheet, context.tr('Titre'), account.title),
              _info(
                  sheet,
                  context.tr('Date de naissance'),
                  account.dateOfBirth == null
                      ? null
                      : DateFormat('d MMMM y', locale).format(account.dateOfBirth!)),
              const Divider(),
            ],
            // An hourly wage lives in the payroll: no row for it once Mara's
            // switchboard hid the payroll (104).
            if (manage && !(m.hourly != null && _payrollHidden))
              ListTile(
                key: const Key('team-action-salary'),
                minVerticalPadding: 14,
                leading: const Icon(Icons.payments_outlined),
                title: Text(context.tr('Salaire')),
                subtitle: m.hourly != null
                    ? Text(context.tr('Payé à l\'heure : se change dans « Paie et journées »'))
                    : null,
                onTap: () => Navigator.pop(sheet, 'salary'),
              ),
            if (manage && account != null) ...[
              ListTile(
                key: const Key('team-action-edit'),
                minVerticalPadding: 14,
                leading: const Icon(Icons.edit_outlined),
                title: Text(context.tr('Modifier les informations')),
                onTap: () => Navigator.pop(sheet, 'edit'),
              ),
              if (roles.isNotEmpty)
                ListTile(
                  key: const Key('team-action-role'),
                  minVerticalPadding: 14,
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(context.tr('Changer la responsabilité')),
                  onTap: () => Navigator.pop(sheet, 'role'),
                ),
              if (canWorker)
                ListTile(
                  key: const Key('team-action-password'),
                  minVerticalPadding: 14,
                  leading: const Icon(Icons.password_outlined),
                  title: Text(context.tr('Réinitialiser le mot de passe')),
                  onTap: () => Navigator.pop(sheet, 'password'),
                ),
            ],
            // A lost phone (075): every session of this person closed.
            if (manage && hasSessions)
              ListTile(
                key: const Key('team-action-signout'),
                minVerticalPadding: 14,
                leading: const Icon(Icons.phonelink_erase_outlined),
                title: Text(context.tr('Déconnecter partout')),
                subtitle: Text(context.tr('Téléphone perdu ou volé')),
                onTap: () => Navigator.pop(sheet, 'signout'),
              ),
            if (!manage)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  m.isOwner
                      ? context.tr('Le propriétaire gère ses propres informations.')
                      : m.isMe
                          ? context.tr('Vos informations se changent dans Compte.')
                          : context.tr('Vous ne pouvez pas modifier ce compte.'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            if (removable) ...[
              ListTile(
                key: const Key('team-action-replace'),
                minVerticalPadding: 14,
                leading: const Icon(Icons.swap_horiz),
                title: Text(context.tr('Remplacer')),
                subtitle: Text(context.tr('Retirer cette personne, puis inviter qui prend sa place')),
                onTap: () => Navigator.pop(sheet, 'replace'),
              ),
              ListTile(
                key: const Key('team-action-remove'),
                minVerticalPadding: 14,
                leading: Icon(Icons.person_remove_outlined, color: theme.colorScheme.error),
                title: Text(context.tr('Retirer de l\'équipe'),
                    style: TextStyle(color: theme.colorScheme.error)),
                onTap: () => Navigator.pop(sheet, 'remove'),
              ),
              if (canWorker && account != null)
                ListTile(
                  key: const Key('team-action-delete'),
                  minVerticalPadding: 14,
                  leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
                  title: Text(context.tr('Supprimer le compte'),
                      style: TextStyle(color: theme.colorScheme.error)),
                  onTap: () => Navigator.pop(sheet, 'delete'),
                ),
            ],
            const SizedBox(height: 8),
          ],
        ),
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'salary':
        if (m.hourly != null) {
          _payroll();
        } else {
          await _salary(m);
        }
      case 'replace':
        if (await _remove(m, replace: true) && mounted) await _invite();
      case 'remove':
        await _remove(m);
      case 'edit':
        await _edit(account!);
      case 'role':
        await _changeRole(m, account!, roles);
      case 'password':
        await _resetPassword(m);
      case 'signout':
        await _signOutEverywhere(m);
      case 'delete':
        await _deleteAccount(m);
    }
  }

  Widget _info(BuildContext ctx, String label, String? value) {
    final theme = Theme.of(ctx);
    final shown = (value != null && value.trim().isNotEmpty) ? value : '—';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(shown, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  /// Says how an action went, then reloads. One place, so every action
  /// reports a refusal the same way.
  Future<void> _act(Future<void> Function() action, {required String done}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      if (mounted) await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  Future<void> _edit(Member account) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditMemberSheet(admin: widget.admin, member: account),
    );
    if (saved == true && mounted) await _load();
  }

  /// The responsibilities below the caller's own; never an owner nor a
  /// super administrator.
  Future<void> _changeRole(TeamMember m, Member account, List<String> roles) async {
    // On the person's current responsibility; none picked when it is not
    // one the caller may give, so the dialog never suggests a wrong one.
    String? selected = roles.contains(account.role) ? account.role : null;
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.tr('Responsabilité de {label}', {'label': m.name})),
        content: StatefulBuilder(
          builder: (_, setInner) => RadioGroup<String>(
            groupValue: selected,
            onChanged: (v) => setInner(() => selected = v ?? selected),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in roles)
                  RadioListTile<String>(
                    key: Key('team-role-$r'),
                    value: r,
                    title: Text(context.tr(roleLabel(r))),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(context.tr('Annuler')),
          ),
          FilledButton(
            key: const Key('team-role-save'),
            onPressed: () => Navigator.pop(dialog, selected),
            child: Text(context.tr('Enregistrer')),
          ),
        ],
      ),
    );
    if (chosen == null || chosen == account.role || !mounted) return;
    await _act(() => widget.admin.setMembershipRole(account.membershipId, chosen),
        done: context.tr('Responsabilité mise à jour.'));
  }

  Future<void> _resetPassword(TeamMember m) async {
    final pw1 = TextEditingController();
    final pw2 = TextEditingController();
    String? error;
    final short = context.tr('Au moins 8 caractères.');
    final differ = context.tr('Les deux ne correspondent pas.');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setInner) => AlertDialog(
          title: Text(context.tr('Nouveau mot de passe — {label}', {'label': m.name})),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pw1,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.tr('Nouveau mot de passe'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pw2,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.tr('Confirmer'),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: TextStyle(color: Theme.of(dialog).colorScheme.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(context.tr('Annuler')),
            ),
            FilledButton(
              onPressed: () {
                if (pw1.text.length < 8) {
                  setInner(() => error = short);
                  return;
                }
                if (pw1.text != pw2.text) {
                  setInner(() => error = differ);
                  return;
                }
                Navigator.pop(dialog, true);
              },
              child: Text(context.tr('Changer')),
            ),
          ],
        ),
      ),
    );
    final password = pw1.text;
    pw1.dispose();
    pw2.dispose();
    if (ok != true || !mounted) return;
    await _act(() => widget.admin.setUserPassword(m.userId, password),
        done: context.tr('Mot de passe changé.'));
  }

  /// A lost phone: closes every session of [m] (075). Their phone asks for
  /// the password again within the hour; nothing they recorded is lost.
  Future<void> _signOutEverywhere(TeamMember m) async {
    final api = AppScope.read(context)?.securityApi;
    if (api == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.tr('Déconnecter {label} partout ?', {'label': m.name})),
        content: Text(context.tr('Tous ses téléphones et navigateurs devront se reconnecter avec le mot de passe, au plus tard dans une heure. Ses accès à l\'entreprise ne changent pas : pour les retirer, utilisez « Retirer de l\'équipe ».')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(context.tr('Annuler'))),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(context.tr('Déconnecter'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final none = context.tr('{label} n\'était connecté nulle part.', {'label': m.name});
    String some(int n) =>
        context.tr('{label} est déconnecté de {n} appareil(s).', {'label': m.name, 'n': n});
    try {
      final n = await api.signOutMember(widget.org.id, m.userId);
      messenger.showSnackBar(SnackBar(content: Text(n == 0 ? none : some(n))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  Future<void> _deleteAccount(TeamMember m) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.tr('Supprimer le compte de {label} ?', {'label': m.name})),
        content: Text(context.tr('Le compte sera supprimé et la personne déconnectée. À sa prochaine connexion, elle arrivera sur la page d\'accueil pour rejoindre une entreprise avec un code ou en demander une.\n\nL\'historique de ce qu\'elle a enregistré reste dans les comptes.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(context.tr('Annuler')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialog).colorScheme.error),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(context.tr('Supprimer')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _act(() => widget.admin.deleteUserAccount(m.userId),
        done: context.tr('Compte supprimé.'));
  }

  /// Every grant of this person in the business: what they recorded stays.
  Future<bool> _remove(TeamMember m, {bool replace = false}) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(replace
            ? context.tr('Remplacer {name} ?', {'name': m.name})
            : context.tr('Retirer {name} de l\'équipe ?', {'name': m.name})),
        content: Text(context.tr('Cette personne ne pourra plus ouvrir l\'entreprise. Tout ce qu\'elle a enregistré reste.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(context.tr('Retour')),
          ),
          FilledButton(
            key: const Key('team-remove-confirm'),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(context.tr('Retirer')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return false;
    try {
      for (final id in m.membershipIds) {
        await widget.admin.revokeMembership(id);
      }
      if (mounted) await _reloadAll();
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
      return false;
    }
  }

  Future<void> _salary(TeamMember m) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SalarySheet(org: widget.org, admin: widget.admin, member: m),
    );
    if (saved == true) await _load();
  }

  /// The same message the invitation was first sent with (017).
  Future<void> _share(TeamInvite inv) => SharePlus.instance.share(ShareParams(
      text: Invitation(
              id: inv.id,
              code: inv.code,
              orgName: _team?.orgName ?? widget.org.name,
              expiresAt: inv.expiresAt)
          .message));

  Future<void> _withdraw(TeamInvite inv) async {
    try {
      await widget.admin.revokeInvitation(inv.id);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  /// Mara's switchboard hid the payroll for this business (104).
  bool get _payrollHidden =>
      AppScope.maybeOf(context)?.session.accessFor(widget.org.id).isHidden('payroll') ??
      false;

  void _payroll() {
    final scope = AppScope.of(context);
    final access = scope.session.accessFor(widget.org.id);
    if (access.isProLocked('payroll')) {
      ProSheet.open(
        context,
        org: widget.org,
        terms: scope.session.planTerms,
        admin: scope.admin,
        canRequest: widget.org.isAdmin,
        feature: 'payroll',
      );
      return;
    }
    context.push(Routes.inside(widget.org.id, 'personnel'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final team = _team;
    final seats = _seats;
    final session = AppScope.maybeOf(context)?.session;
    final payrollLocked =
        session?.accessFor(widget.org.id).isProLocked('payroll') ?? false;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: Text(context.tr('Équipe'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_loading && team == null) const LinearProgressIndicator(),
            if (seats != null) ...[
              SeatCard(
                seats: seats,
                onUnlock: _unlock,
                onFinishSetup: _finishSetup,
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                key: const Key('team-add'),
                onPressed: _add,
                icon: Icon(seats == null || seats.open
                    ? Icons.person_add_alt_1
                    : Icons.lock_outline),
                label: Text(context.tr('Ajouter une personne'),
                    style: const TextStyle(fontSize: 17)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (team != null) ...[
              const SizedBox(height: 20),
              _label(theme, context.tr('Les personnes')),
              KajCard(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, m) in team.members.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 72),
                      _MemberRow(
                        member: m,
                        currency: widget.org.currency,
                        showPay: _seesPay(m),
                        scope: _scopeLine(m),
                        onTap: () => _member(m),
                      ),
                    ],
                  ],
                ),
              ),
              if (team.invitations.isNotEmpty) ...[
                const SizedBox(height: 20),
                _label(theme, context.tr('Invitations en attente')),
                KajCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, inv) in team.invitations.indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 72),
                        _InviteRow(
                          invite: inv,
                          onShare: () => _share(inv),
                          onWithdraw: () => _withdraw(inv),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
            if (!_payrollHidden) ...[
              const SizedBox(height: 20),
              _label(theme, context.tr('Payer')),
              KajCard(
                margin: EdgeInsets.zero,
                child: ListTile(
                  key: const Key('team-payroll'),
                  minVerticalPadding: 14,
                  leading: const CircleAvatar(
                    backgroundColor: maraPaper,
                    child: Icon(Icons.payments_outlined, color: maraDeep),
                  ),
                  title: Text(context.tr('Paie et journées')),
                  subtitle: Text(context.tr('Payer un salaire, noter une journée, les personnes sans compte')),
                  trailing: payrollLocked
                      ? ProCostBadge(
                          cost: session?.featuresFor(widget.org.id)?.toolOf('payroll')?.cost)
                      : const Icon(Icons.chevron_right),
                  onTap: _payroll,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _label(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(text.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700)),
      );
}

/// What the team may hold now: the free person, the lock with Pro and the
/// cauris price, or « sans limite » — each said once.
class SeatCard extends StatelessWidget {
  const SeatCard({
    super.key,
    required this.seats,
    required this.onUnlock,
    this.onFinishSetup,
  });

  final TeamSeats seats;
  final VoidCallback onUnlock;

  /// Before the first setup: the way to finish it. Null draws no button.
  final VoidCallback? onFinishSetup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String title;
    final String line;
    String? count;
    if (seats.unlimited) {
      title = context.tr('Équipe sans limite');
      line = seats.until == null
          ? context.tr('Avec Mara Pro, ajoutez autant de personnes que vous voulez.')
          : seats.gift
              ? context.tr('Offert par Mara jusqu\'au {date}', {'date': _date(seats.until!)})
              : context.tr('Débloquée avec vos cauris jusqu\'au {date}',
                  {'date': _date(seats.until!)});
    } else if (!seats.setupDone) {
      title = context.tr('1 personne offerte');
      line = context.tr('Elle s\'ouvre une fois la mise en route terminée.');
    } else if (seats.open) {
      title = seats.free > 1
          ? context.tr('{n} personnes offertes', {'n': seats.free})
          : context.tr('1 personne offerte');
      count = seats.used == 0
          ? context.tr('Place libre')
          : context.tr('{used} / {free}', {'used': seats.used, 'free': seats.free});
      line = context.tr('En plus de vous, sans rien payer.');
    } else {
      title = context.tr('Votre personne offerte est là');
      // Kept from before (nobody is removed): said as it is.
      count = seats.used > seats.free
          ? context.tr('{used} personnes (limite : {free})',
              {'used': seats.used, 'free': seats.free})
          : context.tr('{used} / {free}', {'used': seats.used, 'free': seats.free});
      line = context.tr('Pour ajouter quelqu\'un d\'autre : Mara Pro, ou l\'équipe débloquée avec des cauris.');
    }
    final locked = !seats.unlimited && !seats.open;
    final setup = !seats.unlimited && !seats.setupDone && onFinishSetup != null;
    return Container(
      key: const Key('team-seats'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: maraDeep,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: locked ? maraBrown : maraCaramel,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(locked ? Icons.lock_outline : Icons.groups_2_outlined,
                    color: locked ? maraPaper : maraDeep, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleMedium?.copyWith(
                            color: maraPaper, fontWeight: FontWeight.w800)),
                    if (count != null)
                      Text(
                        count,
                        key: const Key('team-seats-count'),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: maraCaramel, fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(line,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: maraPaper.withValues(alpha: 0.85))),
          if (setup) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('team-finish-setup'),
                style: FilledButton.styleFrom(
                    backgroundColor: maraCaramel,
                    foregroundColor: maraDeep,
                    minimumSize: const Size.fromHeight(48)),
                onPressed: onFinishSetup,
                icon: const Icon(Icons.flag_outlined),
                label: Text(context.tr('Terminer la mise en route')),
              ),
            ),
          ],
          if (locked) ...[
            SizedBox(height: setup ? 6 : 12),
            // At least a thumb high, taller when the price takes two lines
            // on a narrow phone.
            SizedBox(
              width: double.infinity,
              child: setup
                  // Second to the setup, which opens the seat for free.
                  ? TextButton.icon(
                      key: const Key('team-unlock'),
                      style: TextButton.styleFrom(
                          foregroundColor: maraCaramel, minimumSize: const Size.fromHeight(48)),
                      onPressed: onUnlock,
                      icon: const Icon(Icons.lock_open),
                      label: Text(_unlockLabel(context), textAlign: TextAlign.center),
                    )
                  : FilledButton.icon(
                      key: const Key('team-unlock'),
                      style: FilledButton.styleFrom(
                          backgroundColor: maraCaramel,
                          foregroundColor: maraDeep,
                          minimumSize: const Size.fromHeight(48),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                      onPressed: onUnlock,
                      icon: const Icon(Icons.lock_open),
                      label: Text(_unlockLabel(context), textAlign: TextAlign.center),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  String _unlockLabel(BuildContext context) => seats.cost == null
      ? context.tr('Débloquer l\'équipe')
      : context.tr('Débloquer l\'équipe ({cost} cauris)', {'cost': seats.cost});

  static String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.currency,
    required this.onTap,
    this.showPay = true,
    this.scope,
  });

  final TeamMember member;
  final String currency;

  /// What the person's grants cover (« Toute l'activité · totaux
  /// seulement »), one line per grant; null when unknown.
  final String? scope;

  /// A salary is shown to the owner, and to whoever outranks the person.
  final bool showPay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = member;
    final money = moneyFormat(currency);
    // The owner's own pay is nobody's line to fill: said only once it is.
    final pay = !showPay
        ? null
        : m.hourly != null
        ? context.tr('{rate} / heure', {'rate': money.format(m.hourly)})
        : m.salary != null
            ? '${money.format(m.salary)} ${periodLabel(context, m.period)}'
            : (m.isOwner ? null : context.tr('Salaire : pas encore noté'));
    return ListTile(
      key: Key('team-member-${m.userId}'),
      minVerticalPadding: 12,
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: m.isOwner ? maraCaramel : maraPaper,
        child: Text(m.name.characters.first.toUpperCase(),
            style: const TextStyle(
                color: maraDeep, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text([
        [context.tr(roleLabel(m.role)), ?pay].join(' · '),
        ?scope,
      ].join('\n')),
      trailing: Icon(Icons.more_vert, color: theme.colorScheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}

/// An invitation still out: whom for, whether it can come in, and the two
/// things to do with it — send it again, or take it back.
class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.invite, required this.onShare, required this.onWithdraw});

  final TeamInvite invite;
  final VoidCallback onShare;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inv = invite;
    return ListTile(
      key: Key('team-invite-${inv.id}'),
      minVerticalPadding: 12,
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: CircleAvatar(
        backgroundColor: inv.blocked ? maraBrown : maraPaper,
        child: Icon(inv.blocked ? Icons.block : Icons.schedule_send_outlined,
            color: inv.blocked ? maraPaper : maraBrown),
      ),
      title: Text(inv.name ?? inv.phone ?? context.tr('Invitation'),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text.rich(TextSpan(children: [
        TextSpan(text: context.tr('Code {code}', {'code': inv.code})),
        const TextSpan(text: ' · '),
        TextSpan(
          text: inv.blocked
              ? context.tr('ne peut pas entrer : place prise')
              : context.tr('en attente'),
          style: TextStyle(
              fontWeight: FontWeight.w700,
              color: inv.blocked ? theme.colorScheme.error : null),
        ),
      ])),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('team-invite-share-${inv.id}'),
            visualDensity: VisualDensity.compact,
            tooltip: context.tr('Renvoyer'),
            icon: const Icon(Icons.send_outlined),
            onPressed: onShare,
          ),
          IconButton(
            key: Key('team-invite-withdraw-${inv.id}'),
            visualDensity: VisualDensity.compact,
            tooltip: context.tr('Annuler l\'invitation'),
            icon: const Icon(Icons.delete_outline),
            onPressed: onWithdraw,
          ),
        ],
      ),
    );
  }
}

/// « / mois », « / semaine », « / jour ».
String periodLabel(BuildContext context, String? period) => switch (period) {
      'week' => context.tr('/ semaine'),
      'day' => context.tr('/ jour'),
      _ => context.tr('/ mois'),
    };

/// A person's salary: an amount and what it is per. Optional, free.
class SalarySheet extends StatefulWidget {
  const SalarySheet({super.key, required this.org, required this.admin, required this.member});

  final OrgSummary org;
  final AdminRepository admin;
  final TeamMember member;

  @override
  State<SalarySheet> createState() => _SalarySheetState();
}

class _SalarySheetState extends State<SalarySheet> {
  late final _amount = TextEditingController(
      text: widget.member.salary == null ? '' : _plain(widget.member.salary!));
  late String _period = widget.member.period ?? 'month';
  bool _busy = false;
  String? _error;

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v';

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save({bool clear = false}) async {
    // « 45 000 », « 45.000 »: forty-five thousand, as written here.
    final amount = clear ? null : parseAmount(_amount.text);
    if (!clear && (amount == null || amount <= 0)) {
      setState(() => _error = context.tr('Entrez un montant.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.admin.setMemberSalary(widget.org.id, widget.member.userId,
          amount: amount, period: _period);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('Salaire de {name}', {'name': widget.member.name}),
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(context.tr('Facultatif. Le noter est gratuit ; le payer passe par la paie.'),
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              key: const Key('salary-amount'),
              controller: _amount,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: theme.textTheme.headlineSmall,
              decoration: InputDecoration(
                labelText: context.tr('Montant'),
                suffixText: widget.org.currency == 'XOF' ? 'F' : widget.org.currency,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              key: const Key('salary-period'),
              // No tick: « par semaine » keeps one line on a 360 dp phone.
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'month', label: Text(context.tr('par mois'))),
                ButtonSegment(value: 'week', label: Text(context.tr('par semaine'))),
                ButtonSegment(value: 'day', label: Text(context.tr('par jour'))),
              ],
              selected: {_period},
              onSelectionChanged:
                  _busy ? null : (s) => setState(() => _period = s.first),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('salary-save'),
                onPressed: _busy ? null : _save,
                child: Text(context.tr('Enregistrer'), style: const TextStyle(fontSize: 17)),
              ),
            ),
            if (widget.member.salary != null)
              TextButton(
                key: const Key('salary-clear'),
                onPressed: _busy ? null : () => _save(clear: true),
                child: Text(context.tr('Effacer le salaire')),
              ),
          ],
        ),
      ),
    );
  }
}
