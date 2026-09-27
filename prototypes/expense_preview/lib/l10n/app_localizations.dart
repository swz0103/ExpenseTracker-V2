import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
    Locale('zh'),
    Locale('zh', 'TW'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'記帳 V2'**
  String get appTitle;

  /// No description provided for @openingDateLabel.
  ///
  /// In zh, this message translates to:
  /// **'起始日期（YYYY-MM-DD）'**
  String get openingDateLabel;

  /// No description provided for @entryDateLabel.
  ///
  /// In zh, this message translates to:
  /// **'日期（YYYY-MM-DD）'**
  String get entryDateLabel;

  /// No description provided for @selectDate.
  ///
  /// In zh, this message translates to:
  /// **'選擇日期'**
  String get selectDate;

  /// No description provided for @confirmDate.
  ///
  /// In zh, this message translates to:
  /// **'確定'**
  String get confirmDate;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @dateHelp.
  ///
  /// In zh, this message translates to:
  /// **'選擇記帳日期'**
  String get dateHelp;

  /// No description provided for @openingDateHelp.
  ///
  /// In zh, this message translates to:
  /// **'選擇起始日期'**
  String get openingDateHelp;

  /// No description provided for @calculateAmount.
  ///
  /// In zh, this message translates to:
  /// **'計算金額'**
  String get calculateAmount;

  /// No description provided for @applyAmount.
  ///
  /// In zh, this message translates to:
  /// **'套用結果'**
  String get applyAmount;

  /// No description provided for @calculationSyntax.
  ///
  /// In zh, this message translates to:
  /// **'請檢查算式、括號與小數點。'**
  String get calculationSyntax;

  /// No description provided for @calculationDivisionByZero.
  ///
  /// In zh, this message translates to:
  /// **'不能除以零，請修改算式。'**
  String get calculationDivisionByZero;

  /// No description provided for @calculationComplexity.
  ///
  /// In zh, this message translates to:
  /// **'算式過長或過於複雜，請分段計算。'**
  String get calculationComplexity;

  /// No description provided for @calculationRange.
  ///
  /// In zh, this message translates to:
  /// **'計算結果超出可保存的金額範圍。'**
  String get calculationRange;

  /// No description provided for @calculationResult.
  ///
  /// In zh, this message translates to:
  /// **'計算結果：{currency} {amount}'**
  String calculationResult(String currency, String amount);

  /// No description provided for @calculationRounded.
  ///
  /// In zh, this message translates to:
  /// **'結果已依 {currency} 小數 {scale} 位四捨五入。'**
  String calculationRounded(String currency, int scale);

  /// No description provided for @calculationPercent.
  ///
  /// In zh, this message translates to:
  /// **'10% = 0.1；折扣例：100 × (1 − 10%)。'**
  String get calculationPercent;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
