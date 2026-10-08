import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/courier/courier_dossier.dart';
import '../../core/l10n/tr.dart';

/// The words a courier's dossier (112) is told in, the same for the person
/// who fills it and for the platform that reviews it.

String courierStepLabel(BuildContext context, String step) => switch (step) {
      'zone' => context.tr('Zone de livraison'),
      'hours' => context.tr('Jours et heures'),
      'vehicle' => context.tr('Véhicule'),
      'selfie' => context.tr('Selfie'),
      'id' => context.tr('Pièce d\'identité'),
      'phone' => context.tr('Numéro WhatsApp'),
      'charter' => context.tr('Charte du livreur'),
      _ => step,
    };

String courierReasonLabel(BuildContext context, String? reason) => switch (reason) {
      'blurry' => context.tr('Photo floue'),
      'unreadable' => context.tr('Pièce illisible'),
      'face' => context.tr('Visage différent de la pièce'),
      'missing' => context.tr('Informations manquantes'),
      'new_selfie' => context.tr('Nouveau selfie demandé'),
      'new_id' => context.tr('Nouvelle photo de la pièce demandée'),
      _ => context.tr('Autre raison'),
    };

String courierVehicleLabel(BuildContext context, String? vehicle) => switch (vehicle) {
      'moto' => context.tr('Moto'),
      'velo' => context.tr('Vélo'),
      'voiture' => context.tr('Voiture'),
      'tricycle' => context.tr('Tricycle'),
      'pied' => context.tr('À pied'),
      _ => '—',
    };

IconData courierVehicleIcon(String? vehicle) => switch (vehicle) {
      'moto' => Icons.two_wheeler,
      'velo' => Icons.pedal_bike,
      'voiture' => Icons.directions_car_outlined,
      'tricycle' => Icons.electric_rickshaw_outlined,
      'pied' => Icons.directions_walk,
      _ => Icons.help_outline,
    };

String courierIdLabel(BuildContext context, String? kind) => switch (kind) {
      'cnib' => context.tr('CNIB'),
      'passeport' => context.tr('Passeport'),
      'carte_consulaire' => context.tr('Carte consulaire'),
      _ => '—',
    };

String courierPartLabel(BuildContext context, String part) => switch (part) {
      'selfie' => context.tr('Selfie'),
      'id_front' => context.tr('Pièce — recto'),
      'id_back' => context.tr('Pièce — verso'),
      'licence' => context.tr('Permis de conduire'),
      _ => part,
    };

const courierDays = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];

String courierDayLabel(BuildContext context, String day) => switch (day) {
      'lun' => context.tr('Lun'),
      'mar' => context.tr('Mar'),
      'mer' => context.tr('Mer'),
      'jeu' => context.tr('Jeu'),
      'ven' => context.tr('Ven'),
      'sam' => context.tr('Sam'),
      'dim' => context.tr('Dim'),
      _ => day,
    };

/// « Lun, Mar, Sam · 07:30 – 19:00 ».
String courierHoursLine(BuildContext context, CourierDossier d) {
  final days = d.days.map((x) => courierDayLabel(context, x)).join(', ');
  final hours = d.hoursFrom == null ? '' : ' · ${d.hoursFrom} – ${d.hoursTo}';
  return '$days$hours';
}

/// « Yamaha Crypton, rouge · 11 KK 2233 ».
String courierVehicleLine(BuildContext context, CourierDossier d) {
  final kind = courierVehicleLabel(context, d.vehicle);
  if (!d.isMotor) return kind;
  return '$kind — ${[d.vehicleMake, d.vehicleModel].whereType<String>().join(' ')}'
      ', ${d.vehicleColour ?? ''} · ${d.vehiclePlate ?? ''}';
}

/// One line of the dossier's history, in words.
String courierEventLabel(BuildContext context, CourierEvent e) => switch (e.kind) {
      'sent' => context.tr('Demande envoyée'),
      'resent' => context.tr('Demande renvoyée'),
      'refused' => context.tr('À corriger : {reason}', {'reason': courierReasonLabel(context, e.reason)}),
      'photo' => courierReasonLabel(context, e.reason),
      'approved' => context.tr('Approuvée : vous êtes livreur'),
      'reopened' => context.tr('De nouveau en cours d\'examen'),
      _ => e.kind,
    };

String courierDate(BuildContext context, DateTime at) =>
    DateFormat('d MMM y · HH:mm', Localizations.localeOf(context).toString()).format(at);

/// The driver charter (version 1), accepted before sending. The version
/// is the server's (courier_rules().charter_version): a new text is a new
/// version, in 112's courier_rules and here together.
List<String> courierCharter(BuildContext context) => [
      context.tr('Je livre ce que la boutique m\'a confié, sans l\'ouvrir ni rien en retirer.'),
      context.tr('J\'encaisse le montant exact affiché dans Mara et je remets à la boutique ce qui lui revient, le jour même.'),
      context.tr('Je respecte le client : je suis poli et à l\'heure, et je ne garde ni son numéro ni son adresse pour autre chose que sa livraison.'),
      context.tr('Je respecte le code de la route, je porte un casque à moto et je ne livre jamais après avoir bu de l\'alcool.'),
      context.tr('Je préviens la boutique et le client en cas de retard ou de problème.'),
      context.tr('Mon compte livreur est personnel : je ne le prête à personne.'),
      context.tr('Un manquement à cette charte peut suspendre mon accès livreur.'),
    ];

/// The history as a column of dots, the current state last.
class CourierTimeline extends StatelessWidget {
  const CourierTimeline({super.key, required this.events, this.now, this.ink = const Color(0xFF0E0D0C)});

  final List<CourierEvent> events;

  /// The state still running (« En cours d'examen »), drawn last, lit.
  final String? now;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String?, bool)>[
      for (final e in events)
        (courierEventLabel(context, e), courierDate(context, e.at), false),
      if (now != null) (now!, null, true),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 24,
                  child: Column(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: rows[i].$3 ? ink : Colors.transparent,
                          border: Border.all(color: ink, width: 2),
                        ),
                      ),
                      if (i < rows.length - 1)
                        Expanded(child: Container(width: 2, color: ink.withValues(alpha: 0.25))),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rows[i].$1,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: rows[i].$3 ? FontWeight.w700 : FontWeight.w500,
                                color: ink)),
                        if (rows[i].$2 != null)
                          Text(rows[i].$2!,
                              style: TextStyle(fontSize: 12, color: ink.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
