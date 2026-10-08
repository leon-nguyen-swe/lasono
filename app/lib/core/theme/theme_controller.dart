import 'package:flutter/material.dart';

/// Which theme the app shows. Dark is the default: a music app is mostly used in dim light.
///
/// The choice is kept in memory only; it is back to dark after a reload. (Storing it would need a package
/// for local storage, and one switch does not justify that yet.)
class ThemeController extends ChangeNotifier {
  ThemeController([ThemeMode initial = ThemeMode.dark]) : _mode = initial;

  ThemeMode _mode;

  ThemeMode get mode => _mode;

  void setMode(ThemeMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
  }

  /// Dark ↔ light. "System" is not offered here, so the switch always does something visible.
  void toggle() => setMode(_mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);
}
