import 'package:flutter/services.dart';

/// What the Android side of the app provides: its private files folder
/// and a Keystore key that needs the fingerprint or face to be used
/// (`MainActivity.kt`).
const platformChannel = MethodChannel('expense_tracker/platform');
