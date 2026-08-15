// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'strings.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class StringsFr extends Strings {
  StringsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Kaj';

  @override
  String get languageName => 'Français';

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
  String get today => 'Aujourd\'hui';

  @override
  String get invoices => 'Factures';

  @override
  String get reports => 'Rapports';

  @override
  String get history => 'Historique';

  @override
  String get photos => 'Photos';

  @override
  String get staffLabel => 'Personnel';

  @override
  String pendingCount(int count) {
    return '$count en attente';
  }

  @override
  String get dayClosed => 'Journée clôturée';

  @override
  String get cancelEntryTitle => 'Annuler cette entrée ?';

  @override
  String get back => 'Retour';

  @override
  String get cancelEntry => 'Annuler l\'entrée';

  @override
  String get transferBetweenCashboxes => 'Transfert entre caisses';

  @override
  String get productsLabel => 'Articles';

  @override
  String get sale => 'Vente';

  @override
  String get photo => 'Photo';

  @override
  String get send => 'Envoyer';

  @override
  String get lossesAvoided => 'Pertes évitées';

  @override
  String get stock => 'Stock';

  @override
  String get flocks => 'Bandes';

  @override
  String get startWithHarvest => 'Commencez par la récolte.';

  @override
  String get nothingCountedToday =>
      'Rien compté aujourd\'hui.\nCommencez par la récolte.';

  @override
  String get stockReceipt => 'Réception de stock';

  @override
  String get feedGiven => 'Aliment distribué';

  @override
  String get mortality => 'Mortalité';

  @override
  String get harvest => 'Récolte';

  @override
  String get eggsCollected => 'œufs ramassés';

  @override
  String get feedOut => 'Aliment sorti';

  @override
  String get received => 'Reçu';

  @override
  String get spent => 'Dépensé';

  @override
  String lowStockOf(String names) {
    return 'Il reste peu de $names.';
  }

  @override
  String moduleComingSoon(String module) {
    return 'Votre compte est bien rattaché à cette activité. Le module $module arrive bientôt — vous pourrez alors enregistrer vos opérations ici.';
  }

  @override
  String get weeklySummary => 'Résumé de la semaine';

  @override
  String get weeklySummarySubtitle => 'À envoyer au pasteur, par WhatsApp';

  @override
  String get balances => 'Soldes';

  @override
  String get balancesSubtitle => 'Espèces, banque, Mobile Money';

  @override
  String get givingStatement => 'Relevé de dons';

  @override
  String get givingStatementSubtitle => 'Pour un membre, sur l\'année';

  @override
  String get journalTitle => 'Journal';

  @override
  String get journalSubtitle => 'Toutes les écritures, dans les mots employés';

  @override
  String get incomeStatement => 'Compte de résultat';

  @override
  String get incomeStatementSubtitle =>
      'Ce qui est entré, ce qui est sorti, ce qu\'il reste';

  @override
  String get balanceSheet => 'Bilan';

  @override
  String get balanceSheetSubtitle =>
      'Ce que possède l\'activité et ce qu\'elle doit';

  @override
  String get chartOfAccounts => 'Plan comptable';

  @override
  String get chartOfAccountsSubtitle =>
      'Les catégories, et le détail de chacune';

  @override
  String get trialBalance => 'Balance générale';

  @override
  String get trialBalanceSubtitle =>
      'La preuve que les comptes sont équilibrés';

  @override
  String get people => 'Personnes';

  @override
  String get peopleSubtitle => 'Membres, rôles et invitations';

  @override
  String get sitesAndDepartments => 'Sites et départements';

  @override
  String get structureSubtitle => 'La structure de l\'activité';

  @override
  String get orgSettingsTitle => 'Paramètres de l\'activité';

  @override
  String get orgSettingsSubtitle => 'Nom et monnaie';

  @override
  String get consoleTitle => 'Console';

  @override
  String get consoleSubtitle =>
      'Journal d\'activité, données, état de l\'appareil';

  @override
  String get creditBook => 'Carnet de crédit';

  @override
  String get creditSale => 'Vente à crédit';

  @override
  String get noDebtors => 'Personne ne vous doit rien. Le carnet est à jour.';

  @override
  String totalOutstanding(String amount) {
    return 'Total dû : $amount';
  }

  @override
  String owedForDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'depuis $days jours',
      one: 'depuis 1 jour',
      zero: 'depuis aujourd\'hui',
    );
    return '$_temp0';
  }

  @override
  String get recordRepayment => 'Enregistrer un remboursement';

  @override
  String get amount => 'Montant';

  @override
  String remainingOf(String amount) {
    return 'Reste dû : $amount';
  }

  @override
  String get customerName => 'Nom du client';

  @override
  String get whatWasSold => 'Ce qui a été vendu';

  @override
  String get whatWasSoldHint => 'Sac de riz, bidon d\'huile…';

  @override
  String get enterCustomerName => 'Entrez le nom du client.';

  @override
  String get enterAmount => 'Entrez un montant valide.';

  @override
  String get enterLabel => 'Entrez un libellé.';

  @override
  String get tontines => 'Tontines';

  @override
  String get newTontine => 'Nouvelle tontine';

  @override
  String get noTontines => 'Aucune tontine pour l\'instant. Créez la première.';

  @override
  String roundN(int n) {
    return 'Tour $n';
  }

  @override
  String get takesThePot => 'Prend la caisse ce tour';

  @override
  String get markPaid => 'A payé';

  @override
  String get closeRound => 'Clore le tour';

  @override
  String get tontineName => 'Nom de la tontine';

  @override
  String get amountPerRound => 'Montant par membre et par tour';

  @override
  String get period => 'Rythme';

  @override
  String get periodDaily => 'Chaque jour';

  @override
  String get periodWeekly => 'Chaque semaine';

  @override
  String get periodMonthly => 'Chaque mois';

  @override
  String get membersInOrder => 'Membres, dans l\'ordre des tours';

  @override
  String get membersInOrderHelp =>
      'Un nom par ligne. Le premier prend la première caisse.';

  @override
  String get needTwoMembers => 'Il faut au moins deux membres.';

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
