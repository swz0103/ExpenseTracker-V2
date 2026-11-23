/// How long things are kept before they go for good.
library;

/// How many days a deleted record stays in the trash, to be restored,
/// before it is removed.
const trashRetentionDays = 30;

/// [trashRetentionDays] as a span of time.
const trashRetention = Duration(days: trashRetentionDays);
