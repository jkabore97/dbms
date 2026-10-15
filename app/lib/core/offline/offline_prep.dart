import 'dart:async';

import '../auth/models.dart';
import '../db/local_db.dart';
import '../farm/farm_repository.dart';
import 'offline_app.dart';

/// « Utiliser Mara sans connexion » — what a business keeps on its phone to
/// work with no signal, prepared once on request rather than for everybody.
///
/// The owner asked: « ask the user after a business creation if they want to
/// be able to use the app offline, then show them a button that will download
/// components for offline use. I don't think shoppers need offline. » So:
///
///   * Asked once per business, per device, of the business's admins only,
///     the first time its home opens (after the first setup). A shopper never
///     reaches a business home and is never asked. (On the web every visitor
///     keeps the part of the app their visits used — web/mara_sw.js, so the
///     street opens at once on a slow line; that is not this.)
///   * « Télécharger pour hors ligne » then prepares, in steps the screen
///     shows: the whole app on the web (both halves and every asset, kept by
///     web/mara_sw.js — on Android the app is already on the phone), the
///     chart of accounts the entry sheets offer offline, and for a farm its
///     stock and flocks.
///   * Compte › Préférences › Hors ligne prepares again, or forgets the copy.
///   * On the web, the browser is asked to keep this site's storage
///     (navigator.storage.persist(), [keepStorage]): at the tap on
///     « Télécharger pour hors ligne », and again when a prepared device
///     opens a business ([keepStorageAtStartup]) — at most once a week,
///     never once the browser has said yes, and never anywhere but a
///     browser (Android and iOS keep an app's files).
class OfflinePrep {
  OfflinePrep({
    required this.db,
    this.farm,
    this.cacheChart,
    Future<bool> Function()? keepStorage,
    Future<bool> Function()? storageKept,
    DateTime Function()? now,
  })  : keepStorage = keepStorage ?? OfflineApp.keepStorage,
        storageKept = storageKept ?? (() => OfflineApp.storageKept),
        _now = now ?? DateTime.now;

  final LocalDb db;
  final FarmRepository? farm;

  /// Asks the browser to keep this site's storage (OfflineApp.keepStorage);
  /// tests give a fake.
  final Future<bool> Function() keepStorage;

  /// Whether it already promised to (OfflineApp.storageKept).
  final Future<bool> Function() storageKept;
  final DateTime Function() _now;

  static const _storageAskedKey = 'storage_persist_asked';

  /// How long after asking the browser it is asked again, at an opening.
  static const storageAskEvery = Duration(days: 7);

  /// SessionController.cacheChart: the chart of accounts into the device.
  final Future<void> Function(OrgSummary org)? cacheChart;

  static String _askedKey(String orgId) => 'offline_asked:$orgId';
  static const _readyKey = 'offline_ready';

  /// Whether to ask this business's admin, on this device, now.
  Future<bool> shouldAsk(OrgSummary org) async {
    if (!org.isAdmin) return false;
    try {
      return await db.readPref(_askedKey(org.id)) == null;
    } catch (_) {
      return false;
    }
  }

  Future<void> markAsked(OrgSummary org) async {
    try {
      await db.writePref(_askedKey(org.id), DateTime.now().toIso8601String());
    } catch (_) {}
  }

  /// When this device was last prepared, or null.
  Future<DateTime?> readyAt() async {
    try {
      final v = await db.readPref(_readyKey);
      return v == null ? null : DateTime.tryParse(v);
    } catch (_) {
      return null;
    }
  }

  /// The steps, in order, for [org] on this platform.
  List<OfflineStep> stepsFor(OrgSummary org) => [
        if (OfflineApp.needsCopy) OfflineStep.app,
        OfflineStep.accounts,
        if (org.profile == 'farm' && farm != null) OfflineStep.farm,
      ];

  /// Runs every step; [onStep] hears each start and end, [onProgress] the
  /// app copy's files. Returns the steps that could not be done (no signal
  /// for one of them is not a failure of the others).
  Future<List<OfflineStep>> prepare(
    OrgSummary org, {
    void Function(OfflineStep step, bool done)? onStep,
    void Function(int done, int total)? onProgress,
  }) async {
    // First, before anything is awaited: the request then carries the
    // person's tap, which is what a browser that asks wants to see.
    _askStorage();
    final failed = <OfflineStep>[];
    for (final step in stepsFor(org)) {
      onStep?.call(step, false);
      var ok = true;
      try {
        switch (step) {
          case OfflineStep.app:
            ok = await OfflineApp.keep(progress: onProgress);
          case OfflineStep.accounts:
            await cacheChart?.call(org);
          case OfflineStep.farm:
            final f = farm!;
            final items = await f.stockOnHand(org.id);
            final flocks = await f.flocks(org.id);
            await db.cacheFarmItems(
                org.id, items.map((i) => i.toCache()).toList());
            await db.cacheFlocks(
                org.id, flocks.map((x) => x.toCache()).toList());
        }
      } catch (_) {
        ok = false;
      }
      if (!ok) failed.add(step);
      onStep?.call(step, true);
    }
    await markAsked(org);
    if (failed.isEmpty) {
      try {
        await db.writePref(_readyKey, DateTime.now().toIso8601String());
      } catch (_) {}
    }
    return failed;
  }

  /// Asks the browser to keep this site's storage, without waiting for
  /// its answer (a browser that asks the person answers when they do).
  void _askStorage() {
    try {
      unawaited(keepStorage().then((_) {}, onError: (Object _) {}));
    } catch (_) {}
    unawaited(() async {
      try {
        await db.writePref(_storageAskedKey, _now().toIso8601String());
      } catch (_) {}
    }());
  }

  /// At an opening, on a device whose business chose to work offline:
  /// asks again if the browser has not promised yet and was not asked in
  /// the last [storageAskEvery]. Never throws, never waits on the person.
  Future<void> keepStorageAtStartup() async {
    try {
      if (await storageKept()) return;
      if (await readyAt() == null) return;
      final last = DateTime.tryParse(await db.readPref(_storageAskedKey) ?? '');
      if (last != null && _now().difference(last) < storageAskEvery) return;
      _askStorage();
    } catch (_) {}
  }

  /// Takes the web copy back off; the data caches stay (they are refreshed
  /// online anyway and cost nothing).
  Future<void> forget() async {
    await OfflineApp.forget();
    try {
      await db.writePref(_readyKey, null);
    } catch (_) {}
  }
}

enum OfflineStep { app, accounts, farm }
