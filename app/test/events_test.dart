import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/events/events_repository.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/events/events_home_screen.dart';
import 'package:kaj_app/features/events/events_screens.dart';
import 'package:kaj_app/features/events/templates_gallery_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// 152 and 153: Événementiel in the app — the Événementiel's home and its
/// bar, « Nouvelle carte » (the words, then the design from the gallery,
/// or the design first), one card's page (preview, link, published,
/// answers), the guests' list, and Réglages' ninth card with its switch.
class _Events extends EventsRepository {
  _Events() : super(null);

  final calls = <String>[];
  final rows = <EventSummary>[];
  final answers = <String, List<EventRsvp>>{};
  final pictures0 = <EventPicture>[];
  Object? failWith;

  @override
  Future<List<EventPicture>> pictures(String eventId) async => List.of(pictures0);

  @override
  String? pictureUrl(String key, {int width = 400}) => null;

  @override
  Future<void> removePicture(String key) async {
    calls.add('remove:$key');
    pictures0.removeWhere((p) => p.key == key);
  }

  @override
  Future<void> setAlbumOn(String id, bool on) async {
    calls.add('album:$id=$on');
  }

  @override
  Future<void> setCard(String id, String card) async {
    calls.add('card:$id=$card');
    final i = rows.indexWhere((r) => r.id == id);
    if (i < 0) return;
    final r = rows[i];
    rows[i] = EventSummary(
      id: r.id, orgId: r.orgId, kind: r.kind, card: card, slug: r.slug, previewToken: r.previewToken,
      editToken: r.editToken, title: r.title, startsAt: r.startsAt, place: r.place, content: r.content, rsvpOn: r.rsvpOn,
      albumOn: r.albumOn, published: r.published, createdAt: r.createdAt,
    );
  }

  @override
  bool get isConfigured => true;

  @override
  Future<bool> isPublic() async => false;

  @override
  Future<List<EventTemplate>> templates() async => knownTemplates;

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
      editToken: 'ed17ed17ed17ed17ed17ed17',
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
      editToken: r.editToken, title: r.title, startsAt: r.startsAt, place: r.place, content: r.content, rsvpOn: r.rsvpOn,
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

  @override
  Future<List<EventRsvp>> allRsvps(String orgId) async {
    if (failWith != null) throw failWith!;
    return [
      for (final e in rows)
        for (final r in answers[e.id] ?? const <EventRsvp>[])
          EventRsvp(
            id: r.id, name: r.name, people: r.people, answer: r.answer, message: r.message,
            extra: r.extra, createdAt: r.createdAt, eventId: e.id, eventTitle: e.title,
          ),
    ];
  }
}

const _org = OrgSummary(id: 'o1', name: 'Awa Événements', slug: 'awa-evenements', profile: 'events', roles: ['owner']);

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
    testWidgets('empty: a word and the button; the words, then the design from the gallery, then the card',
        (tester) async {
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
      await tester.tap(find.byKey(const Key('event-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anniversaire').last);
      await tester.pumpAndSettle();
      // « Choisir le modèle »: the gallery, for this card, the birthday's
      // design first.
      expect(find.text('Choisir le modèle'), findsOneWidget);
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gallery-for')), findsOneWidget);
      expect(find.text('Le modèle de « Inès & Thomas »'), findsOneWidget);
      expect(find.byKey(const Key('gallery-tabs')), findsOneWidget);
      expect(find.byKey(const Key('template-anniv')), findsOneWidget);
      expect(repo.calls, isEmpty, reason: 'nothing created before a design is chosen');
      // A tap shows the design large (155b); the button creates the card.
      await tester.tap(find.byKey(const Key('template-anniv')));
      await tester.pumpAndSettle();
      expect(find.text('Créer la carte avec ce modèle'), findsOneWidget);
      expect(repo.calls, isEmpty, reason: 'nothing created before the button');
      await tester.tap(find.byKey(const Key('template-use')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['create:Inès & Thomas/anniversaire/anniv/-/Villa Serena']);
      // Opened on the new card's page.
      expect(find.byKey(const Key('event-preview')), findsOneWidget);
      expect(find.text('Brouillon'), findsOneWidget);
      expect(find.textContaining('modèle Trente'), findsOneWidget);
      // Back: the list has it.
      Navigator.of(tester.element(find.byKey(const Key('event-preview')))).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('event-e1')), findsOneWidget);
      expect(find.text('Inès & Thomas'), findsOneWidget);
    });

    testWidgets('the animated family is the gallery\'s second tab, the Premium films marked', (tester) async {
      final repo = _Events();
      await _pump(tester, TemplatesGalleryScreen(
          events: repo, org: _org, draft: const EventDraft(title: 'Gala', kind: 'gala')));
      expect(find.byKey(const Key('template-come')), findsOneWidget);
      expect(find.byKey(const Key('template-anime_lotus_p')), findsNothing);
      await tester.tap(find.byKey(const Key('family-anime')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('template-anime_lettre')), findsOneWidget);
      await tester.dragUntilVisible(
          find.byKey(const Key('template-anime_lotus_p')), find.byType(GridView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('template-anime_lotus_p')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('template-anime_lotus_p')), findsOneWidget);
      expect(find.text('Premium'), findsWidgets);
      await tester.tap(find.byKey(const Key('template-anime_lotus_p')));
      await tester.pumpAndSettle();
      expect(find.text('Étang de lotus'), findsWidgets);
      await tester.tap(find.byKey(const Key('template-use')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['create:Gala/gala/anime_lotus_p/-/-']);
    });

    testWidgets('browsing the designs: one chosen first, then the words, then the card', (tester) async {
      final repo = _Events();
      await _pump(tester, TemplatesGalleryScreen(events: repo, org: _org, now: () => DateTime(2026, 10, 31)));
      expect(find.text('Modèles'), findsOneWidget);
      await tester.tap(find.byKey(const Key('template-come')));
      await tester.pumpAndSettle();
      expect(find.text('Utiliser ce modèle'), findsOneWidget);
      await tester.tap(find.byKey(const Key('template-use')));
      await tester.pumpAndSettle();
      // No card yet: « Pour quelle carte ? » offers a new one only.
      expect(find.text('Pour quelle carte ?'), findsOneWidget);
      expect(find.byKey(const Key('use-new-card')), findsOneWidget);
      expect(find.byKey(const Key('use-card-e1')), findsNothing);
      await tester.tap(find.byKey(const Key('use-new-card')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('event-card-chosen')), findsOneWidget);
      expect(find.text('Modèle : Côme'), findsOneWidget);
      expect(find.text('Créer la carte'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('event-title')), 'Inès & Thomas');
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['create:Inès & Thomas/mariage/come/-/-']);
      expect(find.byKey(const Key('event-preview')), findsOneWidget);
    });

    testWidgets('browsing with a card already made: « Pour quelle carte ? » gives it the design, its words kept',
        (tester) async {
      final repo = _Events();
      final e = await repo.create(
          orgId: 'o1', title: 'Inès & Thomas', kind: 'mariage', card: 'come',
          startsAt: DateTime(2027, 6, 5, 15), place: 'Villa Serena');
      await _pump(tester, TemplatesGalleryScreen(events: repo, org: _org, now: () => DateTime(2026, 10, 31)));
      await tester.tap(find.byKey(const Key('template-ravello')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('template-use')));
      await tester.pumpAndSettle();
      expect(find.text('Pour quelle carte ?'), findsOneWidget);
      expect(find.byKey(Key('use-card-${e.id}')), findsOneWidget);
      expect(find.text('Inès & Thomas'), findsOneWidget);
      await tester.tap(find.byKey(Key('use-card-${e.id}')));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'card:${e.id}=ravello');
      // On the card's page, with its new design and its own words.
      expect(find.byKey(const Key('event-preview')), findsOneWidget);
      expect(find.textContaining('modèle Ravello'), findsOneWidget);
      expect(find.text('Villa Serena'), findsOneWidget);
    });

    testWidgets('« Changer de modèle » on a card: the gallery for it, the current design marked, another chosen',
        (tester) async {
      final repo = _Events();
      final e = await repo.create(
          orgId: 'o1', title: 'Inès & Thomas', kind: 'mariage', card: 'come',
          startsAt: DateTime(2027, 6, 5, 15), place: 'Villa Serena');
      await _pump(tester, EventScreen(events: repo, org: _org, eventId: e.id, open: (u) async {}));
      expect(find.textContaining('modèle Côme'), findsOneWidget);
      await tester.tap(find.byKey(const Key('event-card-change')));
      await tester.pumpAndSettle();
      expect(find.text('Changer de modèle'), findsWidgets);
      expect(find.text('Le modèle de « Inès & Thomas »'), findsOneWidget);
      expect(find.text('Actuel'), findsOneWidget, reason: 'the card\'s design today, marked');
      // The current design cannot be chosen again.
      await tester.tap(find.byKey(const Key('template-come')));
      await tester.pumpAndSettle();
      expect(find.text('Le modèle actuel de cette carte'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('template-use'))).onPressed, isNull);
      Navigator.of(tester.element(find.byKey(const Key('template-use')))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('template-ravello')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('template-use')));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'card:e1=ravello');
      expect(find.text('Modèle changé'), findsOneWidget);
      expect(find.textContaining('modèle Ravello'), findsOneWidget);
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

  group('the Événementiel\'s home', () {
    testWidgets('its bar: Cartes, Modèles, Invités, Plus; the cards under it; « Nouvelle carte »', (tester) async {
      final repo = _Events();
      await repo.create(orgId: 'o1', title: 'Inès & Thomas', kind: 'mariage', card: 'come');
      await _pump(tester, EventsHomeScreen(org: _org, events: repo));
      expect(find.text('Awa Événements'), findsOneWidget);
      expect(find.text('Cartes'), findsOneWidget);
      expect(find.text('Modèles'), findsOneWidget);
      expect(find.text('Invités'), findsOneWidget);
      expect(find.text('Plus'), findsOneWidget);
      expect(find.byKey(const Key('event-e1')), findsOneWidget);
      expect(find.byKey(const Key('event-new')), findsOneWidget);
      // No till, no stock, no vitrine on this bar.
      expect(find.text('Vendre'), findsNothing);
      expect(find.text('Stock'), findsNothing);
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
      // The answers sit under the buttons and their hints: the list builds them on scroll.
      await tester.scrollUntilVisible(find.text('Réponses des invités · 2'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Réponses des invités · 2'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Tanti Rose'), 200, scrollable: find.byType(Scrollable).first);
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
      expect(opened.single.queryParameters.containsKey('modifier'), isFalse, reason: 'a look is not an edit');

      // « Modifier la carte » (154): the page's own editor, with the edit token.
      await tester.tap(find.byKey(const Key('event-edit')));
      await tester.pumpAndSettle();
      expect(opened, hasLength(2));
      expect(opened.last.path, '/e/${e.slug}');
      expect(opened.last.queryParameters['apercu'], 'f00dbabef00dbabef00dbabe');
      expect(opened.last.queryParameters['modifier'], 'ed17ed17ed17ed17ed17ed17');
      expect(find.textContaining('touchez un texte pour l’écrire'), findsOneWidget);

      // A draft: the copied link is the preview's, and says so.
      expect(find.textContaining('Brouillon : le lien copié est celui de l’aperçu'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('event-published')));
      await tester.tap(find.byKey(const Key('event-published')));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'publish:${e.id}=true');
      expect(find.text('Le lien à envoyer aux invités : la carte est publiée.'), findsOneWidget);
      expect(find.text('Publiée'), findsOneWidget);
    });

    testWidgets('the guests\' album (155): the switch, the pictures with their names, one removed', (tester) async {
      final repo = _Events();
      final e = await repo.create(
          orgId: 'o1', title: 'Inès & Thomas', kind: 'mariage', card: 'come',
          startsAt: DateTime(2027, 6, 5, 15), place: 'Villa Serena');
      repo.pictures0.addAll([
        EventPicture(key: 'events/e1/aaaa.jpg', guest: 'Tanti Rose', bytes: 1000, doneAt: DateTime(2027, 6, 5, 16)),
        EventPicture(key: 'events/e1/bbbb.jpg', guest: null, bytes: 1000, doneAt: DateTime(2027, 6, 5, 17)),
      ]);
      await _pump(tester, EventScreen(events: repo, org: _org, eventId: e.id, open: (u) async {}));
      await tester.scrollUntilVisible(find.text('Album des invités · 2'), 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('Tanti Rose'), findsOneWidget);
      expect(find.text('Un invité'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('picture-remove-events/e1/aaaa.jpg')));
      await tester.tap(find.byKey(const Key('picture-remove-events/e1/aaaa.jpg')));
      await tester.pumpAndSettle();
      expect(find.text('Retirer cette photo ?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Retirer'));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'remove:events/e1/aaaa.jpg');
      expect(find.text('Album des invités · 1'), findsOneWidget);
      expect(find.text('Tanti Rose'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('event-album-on')));
      await tester.tap(find.byKey(const Key('event-album-on')));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'album:${e.id}=false');
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

  group('the guests', () {
    testWidgets('every answer across the cards, each under its card; empty, a word', (tester) async {
      final repo = _Events();
      await _pump(tester, GuestsScreen(events: repo, org: _org));
      expect(find.byKey(const Key('guests-empty')), findsOneWidget);
      final a = await repo.create(orgId: 'o1', title: 'Inès & Thomas', kind: 'mariage', card: 'come');
      final b = await repo.create(orgId: 'o1', title: 'Gala des Anciens', kind: 'gala', card: 'anime_lotus_p');
      repo.answers[a.id] = [
        EventRsvp(id: 'r1', name: 'Tanti Rose', people: 2, answer: 'oui', message: null, extra: const {}, createdAt: DateTime(2026, 11, 1)),
      ];
      repo.answers[b.id] = [
        EventRsvp(id: 'r2', name: 'Salif', people: 1, answer: 'non', message: null, extra: const {}, createdAt: DateTime(2026, 11, 2)),
      ];
      // A new screen (its own key): the first one's state would stay.
      await _pump(tester, GuestsScreen(key: const ValueKey('again'), events: repo, org: _org));
      expect(find.text('Réponses des invités · 2'), findsOneWidget);
      expect(find.text('Tanti Rose'), findsOneWidget);
      expect(find.textContaining('Inès & Thomas'), findsOneWidget);
      expect(find.text('Salif'), findsOneWidget);
      expect(find.textContaining('Gala des Anciens'), findsOneWidget);
    });
  });

  group('the repository', () {
    test('the phone\'s offset for the day, as the server takes it', () {
      // A local time: the offset is this machine's for that day — well-formed
      // whatever it is.
      final s = EventsRepository.offsetOf(DateTime(2026, 12, 12, 23));
      expect(s, matches(RegExp(r'^[+-]\d\d:\d\d$')));
      final utc = DateTime.utc(2026, 12, 12, 23);
      expect(EventsRepository.offsetOf(utc), '+00:00');
    });

    test('the forty-seven templates the app knows: twelve cards, twenty-one layouts, fourteen Premium', () {
      expect(knownTemplates, hasLength(47));
      expect(knownTemplates.where((t) => !t.isAnimated), hasLength(12));
      expect(knownTemplates.where((t) => t.isAnimated && !t.premium), hasLength(21));
      expect(knownTemplates.where((t) => t.premium), hasLength(14));
      expect({for (final t in knownTemplates) t.key}, hasLength(47), reason: 'keys unique');
      expect(eventCardName('anime_lotus_p'), 'Étang de lotus');
      expect(eventCardName('anniv'), 'Trente');
      expect(EventTemplate.fromJson(const {'key': 'x', 'family': 'anime', 'name': 'X', 'premium': true}).previewPath(),
          '/cartes/apercu/x.jpg');
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
