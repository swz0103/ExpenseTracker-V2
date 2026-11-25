/// An exception the app throws itself whose words (its `toString`) are
/// written by the app's code: kinds, counts, field names, an HTTP status,
/// never anything the person, a file or a server wrote. Of exceptions,
/// only these keep their words in the error log (`ErrorLog.describe`);
/// any other keeps its type alone, with an errno or a channel's code.
abstract interface class AppFault implements Exception {}

/// An app fault that carries what another part threw ([cause]): the log
/// keeps its type and what it keeps of the cause, never the cause's own
/// words unless that is an [AppFault] too.
abstract interface class CarriedFault implements AppFault {
  Object get cause;
}
