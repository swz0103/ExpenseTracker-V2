// Ledger owns transaction-to-Merchant references; Merchants owns the identity/history.
const merchantReferenceColumns = [
  'workspace',
  'event_id',
  'merchant_id',
  'merchant_version',
  'merchant_sequence',
];
const merchantReferenceSchema = '''CREATE TABLE event_merchants (
 workspace TEXT NOT NULL, event_id TEXT NOT NULL, merchant_id TEXT NOT NULL,
 merchant_version INTEGER NOT NULL CHECK(merchant_version>0), merchant_sequence INTEGER NOT NULL CHECK(merchant_sequence>0),
 PRIMARY KEY(workspace,event_id),
 FOREIGN KEY(workspace,event_id) REFERENCES events(workspace,id),
 FOREIGN KEY(workspace,merchant_id) REFERENCES merchants(workspace,id)) STRICT''';
