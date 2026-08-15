import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'strings_dyu.dart';
import 'strings_en.dart';
import 'strings_fr.dart';
import 'strings_mos.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of Strings
/// returned by `Strings.of(context)`.
///
/// Applications need to include `Strings.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/strings.dart';
///
/// return MaterialApp(
///   localizationsDelegates: Strings.localizationsDelegates,
///   supportedLocales: Strings.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the Strings.supportedLocales
/// property.
abstract class Strings {
  Strings(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static Strings of(BuildContext context) {
    return Localizations.of<Strings>(context, Strings)!;
  }

  static const LocalizationsDelegate<Strings> delegate = _StringsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('dyu'),
    Locale('en'),
    Locale('fr'),
    Locale('mos')
  ];

  /// No description provided for @appTitle.
  ///
  /// In fr, this message translates to:
  /// **'Kaj'**
  String get appTitle;

  /// This language's own name, in itself — shown in the language picker so somebody who cannot read the current language can still find their own.
  ///
  /// In fr, this message translates to:
  /// **'Français'**
  String get languageName;

  /// No description provided for @signInTagline.
  ///
  /// In fr, this message translates to:
  /// **'Connectez-vous pour ouvrir votre activité.'**
  String get signInTagline;

  /// No description provided for @signUpTagline.
  ///
  /// In fr, this message translates to:
  /// **'Créez votre compte. Vous rejoindrez une activité ensuite, avec un code.'**
  String get signUpTagline;

  /// No description provided for @signIn.
  ///
  /// In fr, this message translates to:
  /// **'Se connecter'**
  String get signIn;

  /// No description provided for @signUp.
  ///
  /// In fr, this message translates to:
  /// **'Créer un compte'**
  String get signUp;

  /// No description provided for @createMyAccount.
  ///
  /// In fr, this message translates to:
  /// **'Créer mon compte'**
  String get createMyAccount;

  /// No description provided for @firstName.
  ///
  /// In fr, this message translates to:
  /// **'Prénom'**
  String get firstName;

  /// No description provided for @middleName.
  ///
  /// In fr, this message translates to:
  /// **'Deuxième prénom (facultatif)'**
  String get middleName;

  /// No description provided for @lastName.
  ///
  /// In fr, this message translates to:
  /// **'Nom de famille'**
  String get lastName;

  /// No description provided for @birthDate.
  ///
  /// In fr, this message translates to:
  /// **'Date de naissance'**
  String get birthDate;

  /// No description provided for @jobTitle.
  ///
  /// In fr, this message translates to:
  /// **'Fonction (facultatif)'**
  String get jobTitle;

  /// No description provided for @jobTitleHint.
  ///
  /// In fr, this message translates to:
  /// **'Vendeuse, gérant, comptable…'**
  String get jobTitleHint;

  /// No description provided for @phoneNumber.
  ///
  /// In fr, this message translates to:
  /// **'Numéro de téléphone'**
  String get phoneNumber;

  /// No description provided for @phoneHint.
  ///
  /// In fr, this message translates to:
  /// **'70 12 34 56'**
  String get phoneHint;

  /// No description provided for @confirmPhone.
  ///
  /// In fr, this message translates to:
  /// **'Confirmez le numéro'**
  String get confirmPhone;

  /// No description provided for @phoneIsForManager.
  ///
  /// In fr, this message translates to:
  /// **'C\'est ce numéro que votre responsable utilisera.'**
  String get phoneIsForManager;

  /// No description provided for @email.
  ///
  /// In fr, this message translates to:
  /// **'E-mail'**
  String get email;

  /// No description provided for @password.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe'**
  String get password;

  /// No description provided for @passwordMin.
  ///
  /// In fr, this message translates to:
  /// **'Au moins 6 caractères'**
  String get passwordMin;

  /// No description provided for @enterFirstName.
  ///
  /// In fr, this message translates to:
  /// **'Entrez votre prénom.'**
  String get enterFirstName;

  /// No description provided for @enterLastName.
  ///
  /// In fr, this message translates to:
  /// **'Entrez votre nom de famille.'**
  String get enterLastName;

  /// No description provided for @enterBirthDate.
  ///
  /// In fr, this message translates to:
  /// **'Indiquez votre date de naissance.'**
  String get enterBirthDate;

  /// No description provided for @enterPhone.
  ///
  /// In fr, this message translates to:
  /// **'Entrez votre numéro de téléphone.'**
  String get enterPhone;

  /// No description provided for @phonesDiffer.
  ///
  /// In fr, this message translates to:
  /// **'Les deux numéros ne sont pas identiques.'**
  String get phonesDiffer;

  /// No description provided for @enterValidEmail.
  ///
  /// In fr, this message translates to:
  /// **'Entrez une adresse e-mail valide.'**
  String get enterValidEmail;

  /// No description provided for @passwordTooShort.
  ///
  /// In fr, this message translates to:
  /// **'Le mot de passe doit contenir au moins 6 caractères.'**
  String get passwordTooShort;

  /// No description provided for @signInRefused.
  ///
  /// In fr, this message translates to:
  /// **'Connexion refusée. Réessayez.'**
  String get signInRefused;

  /// No description provided for @accountCreated.
  ///
  /// In fr, this message translates to:
  /// **'Compte créé'**
  String get accountCreated;

  /// No description provided for @confirmEmailSent.
  ///
  /// In fr, this message translates to:
  /// **'Un message a été envoyé à {email}. Ouvrez le lien qu\'il contient, puis revenez vous connecter.'**
  String confirmEmailSent(String email);

  /// No description provided for @serverNotConfigured.
  ///
  /// In fr, this message translates to:
  /// **'Serveur non configuré'**
  String get serverNotConfigured;

  /// No description provided for @pinEnter.
  ///
  /// In fr, this message translates to:
  /// **'Entrez votre code'**
  String get pinEnter;

  /// No description provided for @pinChoose.
  ///
  /// In fr, this message translates to:
  /// **'Choisissez un code'**
  String get pinChoose;

  /// No description provided for @pinConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Confirmez le code'**
  String get pinConfirm;

  /// No description provided for @pinConfirmSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Entrez-le une seconde fois.'**
  String get pinConfirmSubtitle;

  /// No description provided for @pinChooseSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Ce code ouvre l\'application quand vous n\'avez pas de réseau.'**
  String get pinChooseSubtitle;

  /// No description provided for @pinMismatch.
  ///
  /// In fr, this message translates to:
  /// **'Les deux codes ne correspondent pas. Recommencez.'**
  String get pinMismatch;

  /// No description provided for @pinNoneStored.
  ///
  /// In fr, this message translates to:
  /// **'Aucun code enregistré sur cet appareil.'**
  String get pinNoneStored;

  /// No description provided for @pinWrong.
  ///
  /// In fr, this message translates to:
  /// **'Code incorrect.'**
  String get pinWrong;

  /// No description provided for @pinForgot.
  ///
  /// In fr, this message translates to:
  /// **'Code oublié ? Se reconnecter'**
  String get pinForgot;

  /// No description provided for @pinReconnect.
  ///
  /// In fr, this message translates to:
  /// **'Se reconnecter'**
  String get pinReconnect;

  /// No description provided for @pickBusiness.
  ///
  /// In fr, this message translates to:
  /// **'Choisissez une activité'**
  String get pickBusiness;

  /// No description provided for @manageBusinesses.
  ///
  /// In fr, this message translates to:
  /// **'Gérer les entreprises'**
  String get manageBusinesses;

  /// No description provided for @newBusiness.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle activité'**
  String get newBusiness;

  /// No description provided for @signOut.
  ///
  /// In fr, this message translates to:
  /// **'Se déconnecter'**
  String get signOut;

  /// No description provided for @church.
  ///
  /// In fr, this message translates to:
  /// **'Église'**
  String get church;

  /// No description provided for @farm.
  ///
  /// In fr, this message translates to:
  /// **'Ferme'**
  String get farm;

  /// No description provided for @shop.
  ///
  /// In fr, this message translates to:
  /// **'Commerce'**
  String get shop;

  /// No description provided for @business.
  ///
  /// In fr, this message translates to:
  /// **'Activité'**
  String get business;

  /// No description provided for @waiting.
  ///
  /// In fr, this message translates to:
  /// **'En attente'**
  String get waiting;

  /// No description provided for @accountReady.
  ///
  /// In fr, this message translates to:
  /// **'Votre compte est prêt'**
  String get accountReady;

  /// No description provided for @accountReadyBody.
  ///
  /// In fr, this message translates to:
  /// **'Vous n\'êtes encore rattaché à aucune activité. Si le responsable vous a remis un code, entrez-le. Sinon, communiquez-lui le numéro ci-dessous.'**
  String get accountReadyBody;

  /// No description provided for @giveThisToManager.
  ///
  /// In fr, this message translates to:
  /// **'À communiquer au responsable'**
  String get giveThisToManager;

  /// No description provided for @createBusiness.
  ///
  /// In fr, this message translates to:
  /// **'Créer une activité'**
  String get createBusiness;

  /// No description provided for @iHaveACode.
  ///
  /// In fr, this message translates to:
  /// **'J\'ai un code'**
  String get iHaveACode;

  /// No description provided for @verify.
  ///
  /// In fr, this message translates to:
  /// **'Vérifier'**
  String get verify;

  /// No description provided for @myProfile.
  ///
  /// In fr, this message translates to:
  /// **'Mes informations'**
  String get myProfile;

  /// No description provided for @inviteSomeone.
  ///
  /// In fr, this message translates to:
  /// **'Inviter quelqu’un'**
  String get inviteSomeone;

  /// No description provided for @applications.
  ///
  /// In fr, this message translates to:
  /// **'Demandes'**
  String get applications;

  /// No description provided for @businesses.
  ///
  /// In fr, this message translates to:
  /// **'Entreprises'**
  String get businesses;

  /// No description provided for @applyForBusiness.
  ///
  /// In fr, this message translates to:
  /// **'Demander une entreprise'**
  String get applyForBusiness;

  /// No description provided for @switchBusiness.
  ///
  /// In fr, this message translates to:
  /// **'Changer d\'activité'**
  String get switchBusiness;

  /// No description provided for @accounting.
  ///
  /// In fr, this message translates to:
  /// **'Comptabilité'**
  String get accounting;

  /// No description provided for @administration.
  ///
  /// In fr, this message translates to:
  /// **'Administration'**
  String get administration;

  /// No description provided for @account.
  ///
  /// In fr, this message translates to:
  /// **'Compte'**
  String get account;

  /// No description provided for @stayConnected.
  ///
  /// In fr, this message translates to:
  /// **'Rester connecté'**
  String get stayConnected;

  /// No description provided for @unsentDataTitle.
  ///
  /// In fr, this message translates to:
  /// **'Des données ne sont pas encore envoyées'**
  String get unsentDataTitle;

  /// No description provided for @unsentDataBody.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 enregistrement attend le réseau.} other{{count} enregistrements attendent le réseau.}} Ces données restent sur cet appareil et seront envoyées à la prochaine connexion de ce compte.\n\nSe déconnecter maintenant ?'**
  String unsentDataBody(int count);

  /// No description provided for @language.
  ///
  /// In fr, this message translates to:
  /// **'Langue'**
  String get language;

  /// No description provided for @languageSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'La langue de cet appareil. Chacun choisit la sienne.'**
  String get languageSubtitle;

  /// No description provided for @languageSystem.
  ///
  /// In fr, this message translates to:
  /// **'Comme le téléphone'**
  String get languageSystem;

  /// No description provided for @languageSystemSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Suit la langue de l\'appareil : {resolved}'**
  String languageSystemSubtitle(String resolved);

  /// No description provided for @today.
  ///
  /// In fr, this message translates to:
  /// **'Aujourd\'hui'**
  String get today;

  /// No description provided for @invoices.
  ///
  /// In fr, this message translates to:
  /// **'Factures'**
  String get invoices;

  /// No description provided for @reports.
  ///
  /// In fr, this message translates to:
  /// **'Rapports'**
  String get reports;

  /// No description provided for @history.
  ///
  /// In fr, this message translates to:
  /// **'Historique'**
  String get history;

  /// No description provided for @photos.
  ///
  /// In fr, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @staffLabel.
  ///
  /// In fr, this message translates to:
  /// **'Personnel'**
  String get staffLabel;

  /// No description provided for @pendingCount.
  ///
  /// In fr, this message translates to:
  /// **'{count} en attente'**
  String pendingCount(int count);

  /// No description provided for @dayClosed.
  ///
  /// In fr, this message translates to:
  /// **'Journée clôturée'**
  String get dayClosed;

  /// No description provided for @cancelEntryTitle.
  ///
  /// In fr, this message translates to:
  /// **'Annuler cette entrée ?'**
  String get cancelEntryTitle;

  /// No description provided for @back.
  ///
  /// In fr, this message translates to:
  /// **'Retour'**
  String get back;

  /// No description provided for @cancelEntry.
  ///
  /// In fr, this message translates to:
  /// **'Annuler l\'entrée'**
  String get cancelEntry;

  /// No description provided for @transferBetweenCashboxes.
  ///
  /// In fr, this message translates to:
  /// **'Transfert entre caisses'**
  String get transferBetweenCashboxes;

  /// No description provided for @productsLabel.
  ///
  /// In fr, this message translates to:
  /// **'Articles'**
  String get productsLabel;

  /// No description provided for @sale.
  ///
  /// In fr, this message translates to:
  /// **'Vente'**
  String get sale;

  /// No description provided for @photo.
  ///
  /// In fr, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @send.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer'**
  String get send;

  /// No description provided for @lossesAvoided.
  ///
  /// In fr, this message translates to:
  /// **'Pertes évitées'**
  String get lossesAvoided;

  /// No description provided for @stock.
  ///
  /// In fr, this message translates to:
  /// **'Stock'**
  String get stock;

  /// No description provided for @flocks.
  ///
  /// In fr, this message translates to:
  /// **'Bandes'**
  String get flocks;

  /// No description provided for @startWithHarvest.
  ///
  /// In fr, this message translates to:
  /// **'Commencez par la récolte.'**
  String get startWithHarvest;

  /// No description provided for @nothingCountedToday.
  ///
  /// In fr, this message translates to:
  /// **'Rien compté aujourd\'hui.\nCommencez par la récolte.'**
  String get nothingCountedToday;

  /// No description provided for @stockReceipt.
  ///
  /// In fr, this message translates to:
  /// **'Réception de stock'**
  String get stockReceipt;

  /// No description provided for @feedGiven.
  ///
  /// In fr, this message translates to:
  /// **'Aliment distribué'**
  String get feedGiven;

  /// No description provided for @mortality.
  ///
  /// In fr, this message translates to:
  /// **'Mortalité'**
  String get mortality;

  /// No description provided for @harvest.
  ///
  /// In fr, this message translates to:
  /// **'Récolte'**
  String get harvest;

  /// No description provided for @eggsCollected.
  ///
  /// In fr, this message translates to:
  /// **'œufs ramassés'**
  String get eggsCollected;

  /// No description provided for @feedOut.
  ///
  /// In fr, this message translates to:
  /// **'Aliment sorti'**
  String get feedOut;

  /// No description provided for @received.
  ///
  /// In fr, this message translates to:
  /// **'Reçu'**
  String get received;

  /// No description provided for @spent.
  ///
  /// In fr, this message translates to:
  /// **'Dépensé'**
  String get spent;

  /// No description provided for @lowStockOf.
  ///
  /// In fr, this message translates to:
  /// **'Il reste peu de {names}.'**
  String lowStockOf(String names);

  /// No description provided for @moduleComingSoon.
  ///
  /// In fr, this message translates to:
  /// **'Votre compte est bien rattaché à cette activité. Le module {module} arrive bientôt — vous pourrez alors enregistrer vos opérations ici.'**
  String moduleComingSoon(String module);

  /// No description provided for @weeklySummary.
  ///
  /// In fr, this message translates to:
  /// **'Résumé de la semaine'**
  String get weeklySummary;

  /// No description provided for @weeklySummarySubtitle.
  ///
  /// In fr, this message translates to:
  /// **'À envoyer au pasteur, par WhatsApp'**
  String get weeklySummarySubtitle;

  /// No description provided for @balances.
  ///
  /// In fr, this message translates to:
  /// **'Soldes'**
  String get balances;

  /// No description provided for @balancesSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Espèces, banque, Mobile Money'**
  String get balancesSubtitle;

  /// No description provided for @givingStatement.
  ///
  /// In fr, this message translates to:
  /// **'Relevé de dons'**
  String get givingStatement;

  /// No description provided for @givingStatementSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Pour un membre, sur l\'année'**
  String get givingStatementSubtitle;

  /// No description provided for @journalTitle.
  ///
  /// In fr, this message translates to:
  /// **'Journal'**
  String get journalTitle;

  /// No description provided for @journalSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Toutes les écritures, dans les mots employés'**
  String get journalSubtitle;

  /// No description provided for @incomeStatement.
  ///
  /// In fr, this message translates to:
  /// **'Compte de résultat'**
  String get incomeStatement;

  /// No description provided for @incomeStatementSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Ce qui est entré, ce qui est sorti, ce qu\'il reste'**
  String get incomeStatementSubtitle;

  /// No description provided for @balanceSheet.
  ///
  /// In fr, this message translates to:
  /// **'Bilan'**
  String get balanceSheet;

  /// No description provided for @balanceSheetSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Ce que possède l\'activité et ce qu\'elle doit'**
  String get balanceSheetSubtitle;

  /// No description provided for @chartOfAccounts.
  ///
  /// In fr, this message translates to:
  /// **'Plan comptable'**
  String get chartOfAccounts;

  /// No description provided for @chartOfAccountsSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Les catégories, et le détail de chacune'**
  String get chartOfAccountsSubtitle;

  /// No description provided for @trialBalance.
  ///
  /// In fr, this message translates to:
  /// **'Balance générale'**
  String get trialBalance;

  /// No description provided for @trialBalanceSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'La preuve que les comptes sont équilibrés'**
  String get trialBalanceSubtitle;

  /// No description provided for @people.
  ///
  /// In fr, this message translates to:
  /// **'Personnes'**
  String get people;

  /// No description provided for @peopleSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Membres, rôles et invitations'**
  String get peopleSubtitle;

  /// No description provided for @sitesAndDepartments.
  ///
  /// In fr, this message translates to:
  /// **'Sites et départements'**
  String get sitesAndDepartments;

  /// No description provided for @structureSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'La structure de l\'activité'**
  String get structureSubtitle;

  /// No description provided for @orgSettingsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Paramètres de l\'activité'**
  String get orgSettingsTitle;

  /// No description provided for @orgSettingsSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Nom et monnaie'**
  String get orgSettingsSubtitle;

  /// No description provided for @consoleTitle.
  ///
  /// In fr, this message translates to:
  /// **'Console'**
  String get consoleTitle;

  /// No description provided for @consoleSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Journal d\'activité, données, état de l\'appareil'**
  String get consoleSubtitle;

  /// No description provided for @creditBook.
  ///
  /// In fr, this message translates to:
  /// **'Carnet de crédit'**
  String get creditBook;

  /// No description provided for @creditSale.
  ///
  /// In fr, this message translates to:
  /// **'Vente à crédit'**
  String get creditSale;

  /// No description provided for @noDebtors.
  ///
  /// In fr, this message translates to:
  /// **'Personne ne vous doit rien. Le carnet est à jour.'**
  String get noDebtors;

  /// No description provided for @totalOutstanding.
  ///
  /// In fr, this message translates to:
  /// **'Total dû : {amount}'**
  String totalOutstanding(String amount);

  /// No description provided for @owedForDays.
  ///
  /// In fr, this message translates to:
  /// **'{days, plural, =0{depuis aujourd\'hui} =1{depuis 1 jour} other{depuis {days} jours}}'**
  String owedForDays(int days);

  /// No description provided for @recordRepayment.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer un remboursement'**
  String get recordRepayment;

  /// No description provided for @amount.
  ///
  /// In fr, this message translates to:
  /// **'Montant'**
  String get amount;

  /// No description provided for @remainingOf.
  ///
  /// In fr, this message translates to:
  /// **'Reste dû : {amount}'**
  String remainingOf(String amount);

  /// No description provided for @customerName.
  ///
  /// In fr, this message translates to:
  /// **'Nom du client'**
  String get customerName;

  /// No description provided for @whatWasSold.
  ///
  /// In fr, this message translates to:
  /// **'Ce qui a été vendu'**
  String get whatWasSold;

  /// No description provided for @whatWasSoldHint.
  ///
  /// In fr, this message translates to:
  /// **'Sac de riz, bidon d\'huile…'**
  String get whatWasSoldHint;

  /// No description provided for @enterCustomerName.
  ///
  /// In fr, this message translates to:
  /// **'Entrez le nom du client.'**
  String get enterCustomerName;

  /// No description provided for @enterAmount.
  ///
  /// In fr, this message translates to:
  /// **'Entrez un montant valide.'**
  String get enterAmount;

  /// No description provided for @enterLabel.
  ///
  /// In fr, this message translates to:
  /// **'Entrez un libellé.'**
  String get enterLabel;

  /// No description provided for @tontines.
  ///
  /// In fr, this message translates to:
  /// **'Tontines'**
  String get tontines;

  /// No description provided for @newTontine.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle tontine'**
  String get newTontine;

  /// No description provided for @noTontines.
  ///
  /// In fr, this message translates to:
  /// **'Aucune tontine pour l\'instant. Créez la première.'**
  String get noTontines;

  /// No description provided for @roundN.
  ///
  /// In fr, this message translates to:
  /// **'Tour {n}'**
  String roundN(int n);

  /// No description provided for @takesThePot.
  ///
  /// In fr, this message translates to:
  /// **'Prend la caisse ce tour'**
  String get takesThePot;

  /// No description provided for @markPaid.
  ///
  /// In fr, this message translates to:
  /// **'A payé'**
  String get markPaid;

  /// No description provided for @closeRound.
  ///
  /// In fr, this message translates to:
  /// **'Clore le tour'**
  String get closeRound;

  /// No description provided for @tontineName.
  ///
  /// In fr, this message translates to:
  /// **'Nom de la tontine'**
  String get tontineName;

  /// No description provided for @amountPerRound.
  ///
  /// In fr, this message translates to:
  /// **'Montant par membre et par tour'**
  String get amountPerRound;

  /// No description provided for @period.
  ///
  /// In fr, this message translates to:
  /// **'Rythme'**
  String get period;

  /// No description provided for @periodDaily.
  ///
  /// In fr, this message translates to:
  /// **'Chaque jour'**
  String get periodDaily;

  /// No description provided for @periodWeekly.
  ///
  /// In fr, this message translates to:
  /// **'Chaque semaine'**
  String get periodWeekly;

  /// No description provided for @periodMonthly.
  ///
  /// In fr, this message translates to:
  /// **'Chaque mois'**
  String get periodMonthly;

  /// No description provided for @membersInOrder.
  ///
  /// In fr, this message translates to:
  /// **'Membres, dans l\'ordre des tours'**
  String get membersInOrder;

  /// No description provided for @membersInOrderHelp.
  ///
  /// In fr, this message translates to:
  /// **'Un nom par ligne. Le premier prend la première caisse.'**
  String get membersInOrderHelp;

  /// No description provided for @needTwoMembers.
  ///
  /// In fr, this message translates to:
  /// **'Il faut au moins deux membres.'**
  String get needTwoMembers;

  /// No description provided for @production.
  ///
  /// In fr, this message translates to:
  /// **'Production'**
  String get production;

  /// No description provided for @newProduction.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle production'**
  String get newProduction;

  /// No description provided for @noProduction.
  ///
  /// In fr, this message translates to:
  /// **'Aucune production enregistrée.\nRecevez d\'abord vos ingrédients en stock, puis enregistrez ici ce que vous fabriquez avec.'**
  String get noProduction;

  /// No description provided for @whatWasMade.
  ///
  /// In fr, this message translates to:
  /// **'Produit fabriqué'**
  String get whatWasMade;

  /// No description provided for @whatWasMadeHint.
  ///
  /// In fr, this message translates to:
  /// **'Gâteau, savon, beurre de karité…'**
  String get whatWasMadeHint;

  /// No description provided for @quantityMade.
  ///
  /// In fr, this message translates to:
  /// **'Quantité fabriquée'**
  String get quantityMade;

  /// No description provided for @ingredientsUsed.
  ///
  /// In fr, this message translates to:
  /// **'Ingrédients utilisés'**
  String get ingredientsUsed;

  /// No description provided for @ingredient.
  ///
  /// In fr, this message translates to:
  /// **'Ingrédient'**
  String get ingredient;

  /// No description provided for @quantity.
  ///
  /// In fr, this message translates to:
  /// **'Quantité'**
  String get quantity;

  /// No description provided for @addIngredient.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un ingrédient'**
  String get addIngredient;

  /// No description provided for @estimatedUnitCost.
  ///
  /// In fr, this message translates to:
  /// **'Coût de revient estimé : {amount} par unité'**
  String estimatedUnitCost(String amount);

  /// No description provided for @unitCostIs.
  ///
  /// In fr, this message translates to:
  /// **'Coût de revient : {amount} / unité'**
  String unitCostIs(String amount);

  /// No description provided for @notifications.
  ///
  /// In fr, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @noNotifications.
  ///
  /// In fr, this message translates to:
  /// **'Rien pour l\'instant. Vous serez prévenu ici : stock bas, crédit soldé, tontine prête à clore, nouvel arrivant.'**
  String get noNotifications;

  /// No description provided for @makeAgain.
  ///
  /// In fr, this message translates to:
  /// **'Refaire'**
  String get makeAgain;

  /// No description provided for @searchProduct.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher un article…'**
  String get searchProduct;

  /// No description provided for @noProductFound.
  ///
  /// In fr, this message translates to:
  /// **'Aucun article trouvé. Recevez-le d\'abord en stock.'**
  String get noProductFound;

  /// No description provided for @salePriceOptional.
  ///
  /// In fr, this message translates to:
  /// **'Prix de vente (facultatif)'**
  String get salePriceOptional;

  /// No description provided for @belowUnitCost.
  ///
  /// In fr, this message translates to:
  /// **'Attention : en dessous du coût de revient.'**
  String get belowUnitCost;

  /// No description provided for @enterProductMade.
  ///
  /// In fr, this message translates to:
  /// **'Indiquez ce qui a été fabriqué.'**
  String get enterProductMade;

  /// No description provided for @enterQuantityMade.
  ///
  /// In fr, this message translates to:
  /// **'Indiquez la quantité fabriquée.'**
  String get enterQuantityMade;

  /// No description provided for @enterIngredients.
  ///
  /// In fr, this message translates to:
  /// **'Ajoutez au moins un ingrédient avec sa quantité.'**
  String get enterIngredients;

  /// No description provided for @save.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In fr, this message translates to:
  /// **'Enregistré'**
  String get saved;

  /// No description provided for @cancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get cancel;

  /// No description provided for @retry.
  ///
  /// In fr, this message translates to:
  /// **'Réessayer'**
  String get retry;

  /// No description provided for @close.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get close;
}

class _StringsDelegate extends LocalizationsDelegate<Strings> {
  const _StringsDelegate();

  @override
  Future<Strings> load(Locale locale) {
    return SynchronousFuture<Strings>(lookupStrings(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['dyu', 'en', 'fr', 'mos'].contains(locale.languageCode);

  @override
  bool shouldReload(_StringsDelegate old) => false;
}

Strings lookupStrings(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'dyu':
      return StringsDyu();
    case 'en':
      return StringsEn();
    case 'fr':
      return StringsFr();
    case 'mos':
      return StringsMos();
  }

  throw FlutterError(
      'Strings.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
