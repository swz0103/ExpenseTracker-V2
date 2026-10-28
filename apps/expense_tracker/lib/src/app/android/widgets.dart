import 'channel.dart';

/// Asks the home-screen widgets to read their snapshot again
/// (`WidgetsPart.kt`); nothing when there are none.
Future<void> androidRefreshWidgets() =>
    platformChannel.invokeMethod<void>('refreshWidgets');
