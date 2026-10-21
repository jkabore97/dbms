import 'package:flutter/material.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/farm/animal_sales.dart';
import '../../core/nav/app_scope.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../cauris/path_card.dart' show PathGate;
import '../common/step_flow.dart';
import '../retail/sale_flow.dart';

/// The farm's « Vente » (115), with its animals (150).
///
/// One place opens it: the home's « Vente », « Vendus vivants » from a
/// batch or a herd, a herd's « Vendre ». It reads what the farm has for
/// sale (« À vendre », as always) and — once the database has 150 — its
/// live groups of animals, both with a bounded wait and the phone's last
/// list when the server does not answer. Before 150 the animals are not
/// offered at all and the till is the one it was.
class FarmTill {
  FarmTill._();

  /// How long the till waits for each list before taking the phone's.
  static const askFor = Duration(seconds: 12);

  /// Opens « Vente ». [animal] (an [AnimalForSale.waitingKey]) opens it with
  /// that group in the basket, [quantity] heads. True once a sale was saved.
  static Future<bool?> open(
    BuildContext context, {
    required OrgSummary org,
    required RetailRepository retail,
    OrgAccess? access,
    String? animal,
    double quantity = 1,
  }) async {
    final scope = AppScope.maybeOf(context);
    final dial = access ?? scope?.session.accessFor(org.id) ?? OrgAccess.allEdit;
    List<Product> products = const [];
    var fromDevice = false;
    final askedShelf = retail.tillProducts(org.id, timeout: askFor);
    final askedAnimals = animalsFor(retail, org);
    try {
      final shelf = await askedShelf;
      products = shelf.products;
      fromDevice = shelf.fromDevice;
    } catch (_) {}
    final animals = await askedAnimals;
    if (!context.mounted) return null;
    return StepFlow.push(
      context,
      SaleFlow(
        orgId: org.id,
        orgName: org.name,
        retail: retail,
        currency: org.currency,
        products: products,
        productsFromDevice: fromDevice || (animals?.fromDevice ?? false),
        farm: true,
        canCredit: dial.canEdit('credits') && !PathGate.locks(context, org, 'credits'),
        // The last answer the device heard when offline (batch 115).
        allowWave: scope?.session.waveAllowedFor(org.id) ?? false,
        animals: animals?.animals ?? const [],
        initialAnimal: animals?.animals.any((a) => a.waitingKey == animal) ?? false ? animal : null,
        initialAnimalQuantity: quantity,
      ),
    );
  }

  /// The farm's groups for sale, or null: not a farm, the database before
  /// 150, or nothing heard and nothing kept. Never throws.
  static Future<AnimalShelf?> animalsFor(RetailRepository retail, OrgSummary org) async {
    if (org.profile != 'farm') return null;
    try {
      return await retail.animalsForSale(org.id, timeout: askFor);
    } catch (_) {
      return null;
    }
  }
}
