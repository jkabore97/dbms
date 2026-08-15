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
