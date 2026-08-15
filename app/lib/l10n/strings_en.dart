// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'strings.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class StringsEn extends Strings {
  StringsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Kaj';

  @override
  String get languageName => 'English';

  @override
  String get signInTagline => 'Sign in to open your business.';

  @override
  String get signUpTagline =>
      'Create your account. You will join a business afterwards, with a code.';

  @override
  String get signIn => 'Sign in';

  @override
  String get signUp => 'Create an account';

  @override
  String get createMyAccount => 'Create my account';

  @override
  String get firstName => 'First name';

  @override
  String get middleName => 'Middle name (optional)';

  @override
  String get lastName => 'Family name';

  @override
  String get birthDate => 'Date of birth';

  @override
  String get jobTitle => 'Role (optional)';

  @override
  String get jobTitleHint => 'Salesperson, manager, accountant…';

  @override
  String get phoneNumber => 'Phone number';

  @override
  String get phoneHint => '70 12 34 56';

  @override
  String get confirmPhone => 'Confirm the number';

  @override
  String get phoneIsForManager => 'This is the number your manager will use.';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Password';

  @override
  String get passwordMin => 'At least 6 characters';

  @override
  String get enterFirstName => 'Enter your first name.';

  @override
  String get enterLastName => 'Enter your family name.';

  @override
  String get enterBirthDate => 'Enter your date of birth.';

  @override
  String get enterPhone => 'Enter your phone number.';

  @override
  String get phonesDiffer => 'The two numbers are not the same.';

  @override
  String get enterValidEmail => 'Enter a valid e-mail address.';

  @override
  String get passwordTooShort => 'The password must be at least 6 characters.';

  @override
  String get signInRefused => 'Sign-in refused. Try again.';

  @override
  String get accountCreated => 'Account created';

  @override
  String confirmEmailSent(String email) {
    return 'A message was sent to $email. Open the link it contains, then come back and sign in.';
  }

  @override
  String get serverNotConfigured => 'Server not configured';

  @override
  String get pinEnter => 'Enter your code';

  @override
  String get pinChoose => 'Choose a code';

  @override
  String get pinConfirm => 'Confirm the code';

  @override
  String get pinConfirmSubtitle => 'Enter it a second time.';

  @override
  String get pinChooseSubtitle =>
      'This code opens the app when you have no network.';

  @override
  String get pinMismatch => 'The two codes do not match. Start again.';

  @override
  String get pinNoneStored => 'No code is stored on this device.';

  @override
  String get pinWrong => 'Wrong code.';

  @override
  String get pinForgot => 'Forgot your code? Sign in again';

  @override
  String get pinReconnect => 'Sign in again';

  @override
  String get pickBusiness => 'Choose a business';

  @override
  String get manageBusinesses => 'Manage businesses';

  @override
  String get newBusiness => 'New business';

  @override
  String get signOut => 'Sign out';

  @override
  String get church => 'Church';

  @override
  String get farm => 'Farm';

  @override
  String get shop => 'Shop';

  @override
  String get business => 'Business';

  @override
  String get waiting => 'Waiting';

  @override
  String get accountReady => 'Your account is ready';

  @override
  String get accountReadyBody =>
      'You do not belong to any business yet. If the manager gave you a code, enter it. Otherwise, give them the number below.';

  @override
  String get giveThisToManager => 'Give this to the manager';

  @override
  String get createBusiness => 'Create a business';

  @override
  String get iHaveACode => 'I have a code';

  @override
  String get verify => 'Check';

  @override
  String get myProfile => 'My details';

  @override
  String get inviteSomeone => 'Invite someone';

  @override
  String get applications => 'Requests';

  @override
  String get businesses => 'Businesses';

  @override
  String get applyForBusiness => 'Request a business';

  @override
  String get switchBusiness => 'Switch business';

  @override
  String get accounting => 'Accounting';

  @override
  String get administration => 'Administration';

  @override
  String get account => 'Account';

  @override
  String get stayConnected => 'Stay signed in';

  @override
  String get unsentDataTitle => 'Some data has not been sent yet';

  @override
  String unsentDataBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count records are waiting for the network.',
      one: '1 record is waiting for the network.',
    );
    return '$_temp0 This data stays on this device and will be sent the next time this account connects.\n\nSign out now?';
  }

  @override
  String get language => 'Language';

  @override
  String get languageSubtitle =>
      'The language of this device. Everyone chooses their own.';

  @override
  String get languageSystem => 'Same as the phone';

  @override
  String languageSystemSubtitle(String resolved) {
    return 'Follows the device language: $resolved';
  }

  @override
  String get today => 'Today';

  @override
  String get invoices => 'Invoices';

  @override
  String get reports => 'Reports';

  @override
  String get history => 'History';

  @override
  String get photos => 'Photos';

  @override
  String get staffLabel => 'Staff';

  @override
  String pendingCount(int count) {
    return '$count waiting';
  }

  @override
  String get dayClosed => 'Day closed';

  @override
  String get cancelEntryTitle => 'Cancel this entry?';

  @override
  String get back => 'Back';

  @override
  String get cancelEntry => 'Cancel the entry';

  @override
  String get transferBetweenCashboxes => 'Transfer between cashboxes';

  @override
  String get productsLabel => 'Products';

  @override
  String get sale => 'Sale';

  @override
  String get photo => 'Photo';

  @override
  String get send => 'Send';

  @override
  String get lossesAvoided => 'Losses avoided';

  @override
  String get stock => 'Stock';

  @override
  String get flocks => 'Flocks';

  @override
  String get startWithHarvest => 'Start with the harvest.';

  @override
  String get nothingCountedToday =>
      'Nothing counted today.\nStart with the harvest.';

  @override
  String get stockReceipt => 'Stock received';

  @override
  String get feedGiven => 'Feed given';

  @override
  String get mortality => 'Mortality';

  @override
  String get harvest => 'Harvest';

  @override
  String get eggsCollected => 'eggs collected';

  @override
  String get feedOut => 'Feed used';

  @override
  String get received => 'Received';

  @override
  String get spent => 'Spent';

  @override
  String lowStockOf(String names) {
    return 'Running low on $names.';
  }

  @override
  String moduleComingSoon(String module) {
    return 'Your account is attached to this business. The $module module is coming soon — you will then be able to record your operations here.';
  }

  @override
  String get weeklySummary => 'Weekly summary';

  @override
  String get weeklySummarySubtitle => 'To send to the pastor, on WhatsApp';

  @override
  String get balances => 'Balances';

  @override
  String get balancesSubtitle => 'Cash, bank, Mobile Money';

  @override
  String get givingStatement => 'Giving statement';

  @override
  String get givingStatementSubtitle => 'For one member, over the year';

  @override
  String get journalTitle => 'Journal';

  @override
  String get journalSubtitle => 'Every entry, in the words people used';

  @override
  String get incomeStatement => 'Income statement';

  @override
  String get incomeStatementSubtitle =>
      'What came in, what went out, what is left';

  @override
  String get balanceSheet => 'Balance sheet';

  @override
  String get balanceSheetSubtitle => 'What the business owns and what it owes';

  @override
  String get chartOfAccounts => 'Chart of accounts';

  @override
  String get chartOfAccountsSubtitle =>
      'The categories, and the detail of each';

  @override
  String get trialBalance => 'Trial balance';

  @override
  String get trialBalanceSubtitle => 'The proof the books are balanced';

  @override
  String get people => 'People';

  @override
  String get peopleSubtitle => 'Members, roles and invitations';

  @override
  String get sitesAndDepartments => 'Sites and departments';

  @override
  String get structureSubtitle => 'The structure of the business';

  @override
  String get orgSettingsTitle => 'Business settings';

  @override
  String get orgSettingsSubtitle => 'Name and currency';

  @override
  String get consoleTitle => 'Console';

  @override
  String get consoleSubtitle => 'Activity log, data, device state';

  @override
  String get save => 'Save';

  @override
  String get saved => 'Saved';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Retry';

  @override
  String get close => 'Close';
}
