import 'package:flutter/scheduler.dart';

/// Completes once the screen is idle: no frame to draw and nothing more
/// urgent queued ([Priority.idle]). What work that can wait, a step at a
/// time, waits for between its steps, so no frame waits for it.
Future<void> whenIdle() =>
    SchedulerBinding.instance.scheduleTask<void>(() {}, Priority.idle);
