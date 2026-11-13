import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

class TaildeckStrings implements UiLocalizations {
  const TaildeckStrings();

  static const delegate = _TaildeckStringsDelegate();

  @override
  String get back => 'Back';
  @override
  String get cancel => 'Cancel';
  @override
  String get clearSearch => 'Clear search';
  @override
  String get close => 'Close';
  @override
  String get copy => 'Copy';
  @override
  String get cut => 'Cut';
  @override
  String get dialog => 'Dialog';
  @override
  String get hidePassword => 'Hide password';
  @override
  String get more => 'More';
  @override
  String get noSearchResults => 'No results';
  @override
  String get paste => 'Paste';
  @override
  String get reset => 'Reset';
  @override
  String get search => 'Search';
  @override
  String get select => 'Select';
  @override
  String get selectAll => 'Select all';
  @override
  String get showLess => 'Show less';
  @override
  String get showMore => 'Show more';
  @override
  String get showPassword => 'Show password';
  @override
  String get sort => 'Sort';
  @override
  String get submit => 'Done';
}

class _TaildeckStringsDelegate extends LocalizationsDelegate<UiLocalizations> {
  const _TaildeckStringsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';

  @override
  Future<UiLocalizations> load(Locale locale) =>
      SynchronousFuture(const TaildeckStrings());

  @override
  bool shouldReload(_TaildeckStringsDelegate old) => false;
}
