// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'strings.dart';

// ignore_for_file: type=lint

/// The translations for Dyula (`dyu`).
class StringsDyu extends Strings {
  StringsDyu([String locale = 'dyu']) : super(locale);

  @override
  String get appTitle => 'Kaj';

  @override
  String get languageName => 'Julakan';

  @override
  String get signInTagline => 'Connectez-vous pour ouvrir votre activité.';

  @override
  String get signUpTagline =>
      'Créez votre compte. Vous rejoindrez une activité ensuite, avec un code.';

  @override
  String get signIn => 'Se connecter';

  @override
  String get signUp => 'Créer un compte';

  @override
  String get createMyAccount => 'Créer mon compte';

  @override
  String get firstName => 'Prénom';

  @override
  String get middleName => 'Deuxième prénom (facultatif)';

  @override
  String get lastName => 'Nom de famille';

  @override
  String get birthDate => 'Date de naissance';

  @override
  String get jobTitle => 'Fonction (facultatif)';

  @override
  String get jobTitleHint => 'Vendeuse, gérant, comptable…';

  @override
  String get phoneNumber => 'Numéro de téléphone';

  @override
  String get phoneHint => '70 12 34 56';

  @override
  String get confirmPhone => 'Confirmez le numéro';

  @override
  String get phoneIsForManager =>
      'C\'est ce numéro que votre responsable utilisera.';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Mot de passe';

  @override
  String get passwordMin => 'Au moins 6 caractères';

  @override
  String get enterFirstName => 'Entrez votre prénom.';

  @override
  String get enterLastName => 'Entrez votre nom de famille.';

  @override
  String get enterBirthDate => 'Indiquez votre date de naissance.';

  @override
  String get enterPhone => 'Entrez votre numéro de téléphone.';

  @override
  String get phonesDiffer => 'Les deux numéros ne sont pas identiques.';

  @override
  String get enterValidEmail => 'Entrez une adresse e-mail valide.';

  @override
  String get passwordTooShort =>
      'Le mot de passe doit contenir au moins 6 caractères.';

  @override
  String get signInRefused => 'Connexion refusée. Réessayez.';

  @override
  String get accountCreated => 'Compte créé';

  @override
  String confirmEmailSent(String email) {
    return 'Un message a été envoyé à $email. Ouvrez le lien qu\'il contient, puis revenez vous connecter.';
  }

  @override
  String get serverNotConfigured => 'Serveur non configuré';

  @override
  String get pinEnter => 'Entrez votre code';

  @override
  String get pinChoose => 'Choisissez un code';

  @override
  String get pinConfirm => 'Confirmez le code';

  @override
  String get pinConfirmSubtitle => 'Entrez-le une seconde fois.';

  @override
  String get pinChooseSubtitle =>
      'Ce code ouvre l\'application quand vous n\'avez pas de réseau.';

  @override
  String get pinMismatch => 'Les deux codes ne correspondent pas. Recommencez.';

  @override
  String get pinNoneStored => 'Aucun code enregistré sur cet appareil.';

  @override
  String get pinWrong => 'Code incorrect.';

  @override
  String get pinForgot => 'Code oublié ? Se reconnecter';

  @override
  String get pinReconnect => 'Se reconnecter';

  @override
  String get pickBusiness => 'Choisissez une activité';

  @override
  String get manageBusinesses => 'Gérer les entreprises';

  @override
  String get newBusiness => 'Nouvelle activité';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get church => 'Église';

  @override
  String get farm => 'Ferme';

  @override
  String get shop => 'Commerce';

  @override
  String get business => 'Activité';

  @override
  String get waiting => 'En attente';

  @override
  String get accountReady => 'Votre compte est prêt';

  @override
  String get accountReadyBody =>
      'Vous n\'êtes encore rattaché à aucune activité. Si le responsable vous a remis un code, entrez-le. Sinon, communiquez-lui le numéro ci-dessous.';

  @override
  String get giveThisToManager => 'À communiquer au responsable';

  @override
  String get createBusiness => 'Créer une activité';

  @override
  String get iHaveACode => 'J\'ai un code';

  @override
  String get verify => 'Vérifier';

  @override
  String get myProfile => 'Mes informations';

  @override
  String get inviteSomeone => 'Inviter quelqu’un';

  @override
  String get applications => 'Demandes';

  @override
  String get businesses => 'Entreprises';

  @override
  String get applyForBusiness => 'Demander une entreprise';

  @override
  String get switchBusiness => 'Changer d\'activité';

  @override
  String get accounting => 'Comptabilité';

  @override
  String get administration => 'Administration';

  @override
  String get account => 'Compte';

  @override
  String get stayConnected => 'Rester connecté';

  @override
  String get unsentDataTitle => 'Des données ne sont pas encore envoyées';

  @override
  String unsentDataBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count enregistrements attendent le réseau.',
      one: '1 enregistrement attend le réseau.',
    );
    return '$_temp0 Ces données restent sur cet appareil et seront envoyées à la prochaine connexion de ce compte.\n\nSe déconnecter maintenant ?';
  }

  @override
  String get language => 'Langue';

  @override
  String get languageSubtitle =>
      'La langue de cet appareil. Chacun choisit la sienne.';

  @override
  String get languageSystem => 'Comme le téléphone';

  @override
  String languageSystemSubtitle(String resolved) {
    return 'Suit la langue de l\'appareil : $resolved';
  }

  @override
  String get save => 'Enregistrer';

  @override
  String get saved => 'Enregistré';

  @override
  String get cancel => 'Annuler';

  @override
  String get retry => 'Réessayer';

  @override
  String get close => 'Fermer';
}
