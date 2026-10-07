import 'package:flutter/widgets.dart';

/// A business drawn to be looked at, not used: « Voir comme le
/// commerçant » (106), where Mara sees a home and Compte exactly as the
/// owner does. Below it, nothing that opens by itself on a home — the
/// offline offer, the « débloqué » moment — may run: each of those writes
/// something (a device's « asked », the owner's « seen ») that belongs to
/// the person who really opens the business.
class LookOnly extends InheritedWidget {
  const LookOnly({super.key, required super.child});

  /// Whether [context] sits inside a look-only preview.
  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LookOnly>() != null;

  @override
  bool updateShouldNotify(LookOnly oldWidget) => false;
}
