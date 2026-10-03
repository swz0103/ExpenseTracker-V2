import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/session.dart';

void main() {
  runApp(ExpenseApp(session: AppSession.preview()));
}
