part of 'compose_form.dart';

// The merchant and tags at the foot of the form.

extension ExtraFields on ComposeForm {
  /// The merchants to tap: the one chosen first, then the most used.
  List<String> merchantChoices() {
    final chosen = merchant;
    return [
      if (chosen.isNotEmpty) chosen,
      for (final name in ledger.entryQueryService.merchants.take(8))
        if (name != chosen) name,
    ];
  }

  /// The tags to tap: those on the entry first, then the others in use.
  List<String> tagChoices() => [
    ...tags,
    for (final tag in ledger.reportService.tags.take(8))
      if (!tags.contains(tag)) tag,
  ];

  /// [name] tapped among the merchants: chosen, or no merchant when it
  /// already was.
  void toggleMerchant(String name) {
    if (name == merchant) {
      merchant = '';
    } else {
      pickMerchant(name);
    }
  }

  /// [tag] tapped among the tags: put on the entry, or taken off.
  void toggleTag(String tag) {
    tags = tags.contains(tag)
        ? [
            for (final t in tags)
              if (t != tag) t,
          ]
        : [...tags, tag];
  }
}
