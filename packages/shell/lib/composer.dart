import 'package:flutter/widgets.dart';
import 'package:kernel/kernel.dart';

/// A value a composer's draft keeps under [id], and how it is kept as
/// JSON: an intent kind's own field, or the value an amender reads
/// (design D: the slot's value is stored with the intent).
final class Slot<T extends Object> {
  const Slot(this.id, {required this.encode, required this.decode});

  final String id;
  final Object? Function(T value) encode;

  /// The value kept, or null when what is kept is not one.
  final T? Function(Object? kept) decode;
}

/// What the composer holds while a person types: values by slot. Slots
/// it does not know (a module taken out) are kept as they came.
final class Draft {
  Draft();

  Draft.fromJson(Map<String, Object?> json) {
    _kept.addAll(json);
  }

  final _kept = <String, Object?>{};

  T? get<T extends Object>(Slot<T> slot) => slot.decode(_kept[slot.id]);

  /// Keeps [value] under [slot]; null takes it away.
  void set<T extends Object>(Slot<T> slot, T? value) {
    if (value == null) {
      _kept.remove(slot.id);
    } else {
      _kept[slot.id] = slot.encode(value);
    }
  }

  Map<String, Object?> toJson() => Map.of(_kept);
}

/// A kind of record the composer offers (支出, 收入, 轉帳, 買進…): it
/// [build]s the intent from a draft, or says nothing while the draft is
/// not one yet, and [open]s a kept intent of its kind as a draft.
final class EntryKind {
  const EntryKind({
    required this.kind,
    required this.label,
    required this.order,
    required this.build,
    required this.open,
  });

  final IntentType kind;
  final String label;
  final int order;
  final LedgerIntent? Function(Draft draft, IntentId id) build;
  final Draft? Function(LedgerIntent intent) open;
}

/// What a field is given to draw: its value, where a change goes, and
/// what is wrong with it, if anything.
final class FieldHost<T extends Object> {
  const FieldHost({required this.value, required this.changed, this.problem});

  final T? value;
  final ValueChanged<T?> changed;
  final String? problem;
}

/// A field of the composer, kept under [slot]. With [kinds] it is a field
/// of those kinds; without, an amendment field, shown when the journal
/// says its amender applies to the draft (`Journal.applicable`), so the
/// form and the rule decide by one test.
final class ComposerField<T extends Object> {
  const ComposerField({
    required this.slot,
    required this.order,
    required this.build,
    this.kinds,
  });

  final Slot<T> slot;
  final int order;
  final Set<IntentType>? kinds;
  final Widget Function(BuildContext context, FieldHost<T> host) build;

  /// This field drawn from [draft], a change kept back into it.
  Widget buildIn(
    BuildContext context,
    Draft draft, {
    required VoidCallback changed,
    String? problem,
  }) => build(
    context,
    FieldHost<T>(
      value: draft.get(slot),
      changed: (value) {
        draft.set(slot, value);
        changed();
      },
      problem: problem,
    ),
  );
}
