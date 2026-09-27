// Ledger owns transaction-to-Tag references; Tags owns the identity/history.
const tagReferenceColumns = [
  'workspace',
  'event_id',
  'tag_id',
  'tag_version',
  'tag_sequence',
];
const tagReferenceSchema = '''CREATE TABLE event_tags (
 workspace TEXT NOT NULL, event_id TEXT NOT NULL, tag_id TEXT NOT NULL,
 tag_version INTEGER NOT NULL CHECK(tag_version>0), tag_sequence INTEGER NOT NULL CHECK(tag_sequence>0),
 PRIMARY KEY(workspace,event_id,tag_id),
 FOREIGN KEY(workspace,event_id) REFERENCES events(workspace,id),
 FOREIGN KEY(workspace,tag_id) REFERENCES tags(workspace,id)) STRICT''';
