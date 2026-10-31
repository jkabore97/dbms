import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/events/events_repository.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/events/events_screens.dart';
import 'package:kaj_app/l10n/strings.dart';

/// 152, piece 1: Événementiel in the app — the list, the new-card sheet,
/// one card's page (preview, link, published, answers), and Réglages'
/// ninth card with its one switch.
class _Events extends EventsRepository {
  _Events() : super(null);

  final calls = <String>[];
  final rows = <EventSummary>[];
  final answers = <String, List<EventRsvp>>{};
  Object? failWith;

  @override
  bool get isConfigured => true;

  @override
  Future<bool> isPublic() async => false;

  @override
  Future<List<EventSummary>> list(String orgId) async {
    if (failWith != null) throw failWith!;
    return [for (final r in rows) if (r.orgId == orgId) r];
  }

  @override
  Future<EventSummary?> find(String id) async {
    for (final r in rows) {
      if (r.id == id) return r;
    }
    return null;
  }

  @override
  Future<EventSummary> create({
    required String orgId,
    required String title,
    required String kind,
    required String card,
    DateTime? startsAt,
    String? place,
  }) async {
    calls.add('create:$title/$kind/$card/${startsAt?.toIso8601String() ?? '-'}/${place ?? '-'}');
    final e = EventSummary(
      id: 'e${rows.length + 1}',
      orgId: orgId,
      kind: kind,
      card: card,
      slug: '${title.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-')}-ab12',
      previewToken: 'f00dbabef00dbabef00dbabe',
      title: title,
      startsAt: startsAt,
      place: place,
      content: {'type': kind, 't:names': title},
      rsvpOn: true,
      albumOn: true,
      published: false,
      createdAt: DateTime(2026, 10, 31),
    );
    rows.insert(0, e);
    return e;
  }

  @override
  Future<void> publish(String id, bool on) async {
    calls.add('publish:$id=$on');
    final i = rows.indexWhere((r) => r.id == id);
    final r = rows[i];
    rows[i] = EventSummary(
      id: r.id, orgId: r.orgId, kind: r.kind, card: r.card, slug: r.slug, previewToken: r.previewToken,
      title: r.title, startsAt: r.startsAt, place: r.place, content: r.content, rsvpOn: r.rsvpOn,
      albumOn: r.albumOn, published: on, createdAt: r.createdAt,
    );
  }

  @override
  Future<void> setRsvpOn(String id, bool on) async {
    calls.add('rsvp_on:$id=$on');
  }

  @override
  Future<void> delete(String id) async {
    calls.add('delete:$id');
    rows.removeWhere((r) => r.id == id);
  }

  @override
  Future<List<EventRsvp>> rsvps(String eventId) async => answers[eventId] ?? const [];
}

const _org = OrgSummary(id: 'o1', name: 'Mariages d\'Awa', slug: 'mariages-awa', profile: 'retail', roles: ['owner']);

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: Strings.localizationsDelegates,
    supportedLocales: Strings.supportedLocales,
    home: home,
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('en', null);
  });

  group('the list and the new card', () {
    testWidgets('empty: a word and the button; the sheet creates a card and opens it', (tester) async {
      final repo = _Events();
      await _pump(tester, EventsScreen(events: repo, org: _org, now: () => DateTime(2026, 10, 31)));
      expect(find.text('Aucune carte pour le moment'), findsOneWidget);
      await tester.tap(find.byKey(const Key('event-new')));
      await tester.pumpAndSettle();
      expect(find.text('Nouvelle carte'), findsWidgets);
      // No name: told, nothing created.
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      expect(find.text('Donnez un nom à l’événement : les prénoms, le nom de la fête.'), findsOneWidget);
      expect(repo.calls, isEmpty);
      await tester.enterText(find.byKey(const Key('event-title')), 'Inès & Thomas');
      await tester.enterText(find.byKey(const Key('event-place')), 'Villa Serena');
      // The kind picks its card: a birthday → « Trente ».
      await tester.tap(find.byKey(const Key('event-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anniversaire').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['create:Inès & Thomas/anniversaire/anniv/-/Villa Serena']);
      // Opened on the new card's page.
      expect(find.byKey(const Key('event-preview')), findsOneWidget);
      expect(find.text('Brouillon'), findsOneWidget);
      // Back: the list has it.
      Navigator.of(tester.element(find.byKey(const Key('event-preview')))).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('event-e1')), findsOneWidget);
      expect(find.text('Inès & Thomas'), findsOneWidget);
    });

    testWidgets('the server refuses: the word, and « Réessayer »', (tester) async {
      final repo = _Events()..failWith = Exception('Réservé aux administrateurs');
      await _pump(tester, EventsScreen(events: repo, org: _org));
      expect(find.textContaining('Réservé aux administrateurs'), findsOneWidget);
      repo.failWith = null;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Aucune carte pour le moment'), findsOneWidget);
    });
  });

  group('one card', () {
    testWidgets('preview opens the site with the token; the link copied is the preview\'s until published; publishing; the answers',
        (tester) async {
      final repo = _Events();
      final e = await repo.create(
          orgId: 'o1', title: 'Inès & Thomas', kind: 'mariage', card: 'come',
          startsAt: DateTime(2027, 6, 5, 15), place: 'Villa Serena');
      repo.answers[e.id] = [
        EventRsvp(id: 'r1', name: 'Tanti Rose', people: 2, answer: 'oui', message: 'Avec joie !', extra: const {'diet': 'sans porc'}, createdAt: DateTime(2026, 11, 1)),
        EventRsvp(id: 'r2', name: 'Cousin Malik', people: 1, answer: 'non', message: null, extra: const {}, createdAt: DateTime(2026, 11, 2)),
      ];
      final opened = <Uri>[];
      await _pump(tester, EventScreen(events: repo, org: _org, eventId: e.id, open: (u) async => opened.add(u)));
      expect(find.text('Inès & Thomas'), findsOneWidget);
      expect(find.textContaining('samedi 5 juin 2027'), findsOneWidget);
      expect(find.text('Villa Serena'), findsOneWidget);
      expect(find.text('Réponses des invités · 2'), findsOneWidget);
      expect(find.text('Tanti Rose'), findsOneWidget);
      expect(find.textContaining('Vient · 2'), findsOneWidget);
      expect(find.textContaining('diet : sans porc'), findsOneWidget);
      // The second answer sits below the fold: the list builds it on scroll.
      await tester.scrollUntilVisible(find.text('Ne viendra pas'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Ne viendra pas'), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('event-preview')));
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(opened.single.path, '/e/${e.slug}');
      expect(opened.single.queryParameters['apercu'], 'f00dbabef00dbabef00dbabe');

      // A draft: the copied link is the preview's, and says so.
      expect(find.textContaining('Brouillon : le lien copié est celui de l’aperçu'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('event-published')));
      await tester.tap(find.byKey(const Key('event-published')));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'publish:${e.id}=true');
      expect(find.text('Le lien à envoyer aux invités : la carte est publiée.'), findsOneWidget);
      expect(find.text('Publiée'), findsOneWidget);
    });

    testWidgets('deleting asks, then leaves the page', (tester) async {
      final repo = _Events();
      final e = await repo.create(orgId: 'o1', title: 'Essai', kind: 'gala', card: 'gala');
      await _pump(tester, EventsScreen(events: repo, org: _org));
      await tester.tap(find.byKey(Key('event-${e.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer cette carte ?'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(repo.rows, hasLength(1));
      await tester.tap(find.byKey(const Key('event-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer').last);
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'delete:${e.id}');
      expect(find.text('Aucune carte pour le moment'), findsOneWidget);
    });
  });

  group('Réglages', () {
    test('the ninth card holds the one switch, a flag, in the list the server test pins', () {
      final def = platformSettingDefs.firstWhere((d) => d.key == 'events_public');
      expect(def.type, SettingType.flag);
      expect(def.group, 'events');
      expect(settingCardOf('events_public')?.key, 'evenements');
      expect(platformSettingDefs.last.key, 'events_public', reason: 'appended, as in test_batch105\'s list');
    });

    test('the kinds and the cards: every card belongs to a kind the presets know', () {
      final kinds = {for (final k in eventKinds) k.$1};
      for (final c in eventCards) {
        expect(kinds, contains(c.$3), reason: c.$1);
      }
      expect(eventCards, hasLength(12));
      expect(eventKinds, hasLength(10));
    });
  });
}
