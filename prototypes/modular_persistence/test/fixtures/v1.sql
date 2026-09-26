-- Frozen from bfc9ec7 with synthetic data only.
BEGIN TRANSACTION;
CREATE TABLE accounts (
    workspace TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL,
    PRIMARY KEY (workspace,id)) STRICT;
INSERT INTO "accounts" VALUES('019f0000-0000-7000-8000-000000000000','019f0000-0000-7000-8000-000000000001','{"name":"Frozen fixture","kind":"bank","currency":"USD","scale":2,"openedOn":"2026-09-26","includeInNetWorth":true,"version":1,"state":"active","closedOn":null,"closingReason":null,"successorId":null}');
CREATE TABLE allocations (
    workspace TEXT NOT NULL, event_id TEXT NOT NULL, category_id TEXT NOT NULL,
    amount INTEGER NOT NULL, PRIMARY KEY(workspace,event_id,category_id),
    FOREIGN KEY(workspace,event_id) REFERENCES events(workspace,id)) STRICT;
CREATE TABLE audit (
    workspace TEXT NOT NULL, operation_id TEXT NOT NULL, entity_id TEXT NOT NULL,
    kind TEXT NOT NULL, recorded_at TEXT NOT NULL,
    PRIMARY KEY(workspace,operation_id),
    FOREIGN KEY(workspace,operation_id) REFERENCES receipts(workspace,operation_id)) STRICT;
INSERT INTO "audit" VALUES('019f0000-0000-7000-8000-000000000000','019f0000-0000-7000-8000-000000000010','019f0000-0000-7000-8000-000000000020','account.open','2026-09-26T13:23:54.836646Z');
INSERT INTO "audit" VALUES('019f0000-0000-7000-8000-000000000000','019f0000-0000-7000-8000-000000000011','019f0000-0000-7000-8000-000000000021','ledger.income','2026-09-26T13:23:54.852649Z');
INSERT INTO "audit" VALUES('019f0000-0000-7000-8000-000000000000','019f0000-0000-7000-8000-000000000012','019f0000-0000-7000-8000-000000000022','ledger.expense','2026-09-26T13:23:54.869208Z');
CREATE TABLE events (
    workspace TEXT NOT NULL, id TEXT NOT NULL, kind TEXT NOT NULL,
    business_date TEXT NOT NULL, income INTEGER NOT NULL, expense INTEGER NOT NULL,
    currency TEXT NOT NULL, scale INTEGER NOT NULL,
    PRIMARY KEY (workspace,id)) STRICT;
INSERT INTO "events" VALUES('019f0000-0000-7000-8000-000000000000','019f0000-0000-7000-8000-000000000020','opening','2026-09-26',0,0,'USD',2);
INSERT INTO "events" VALUES('019f0000-0000-7000-8000-000000000000','019f0000-0000-7000-8000-000000000021','income','2026-09-26',2000,0,'USD',2);
INSERT INTO "events" VALUES('019f0000-0000-7000-8000-000000000000','019f0000-0000-7000-8000-000000000022','expense','2026-09-26',0,500,'USD',2);
CREATE TABLE legs (
    workspace TEXT NOT NULL, event_id TEXT NOT NULL, ordinal INTEGER NOT NULL,
    account_id TEXT NOT NULL, amount INTEGER NOT NULL, currency TEXT NOT NULL,
    scale INTEGER NOT NULL, role TEXT NOT NULL,
    PRIMARY KEY (workspace,event_id,ordinal),
    FOREIGN KEY (workspace,event_id) REFERENCES events(workspace,id),
    FOREIGN KEY (workspace,account_id) REFERENCES accounts(workspace,id)) STRICT;
INSERT INTO "legs" VALUES('019f0000-0000-7000-8000-000000000000','019f0000-0000-7000-8000-000000000020',0,'019f0000-0000-7000-8000-000000000001',10000,'USD',2,'principal');
INSERT INTO "legs" VALUES('019f0000-0000-7000-8000-000000000000','019f0000-0000-7000-8000-000000000021',0,'019f0000-0000-7000-8000-000000000001',2000,'USD',2,'principal');
INSERT INTO "legs" VALUES('019f0000-0000-7000-8000-000000000000','019f0000-0000-7000-8000-000000000022',0,'019f0000-0000-7000-8000-000000000001',-500,'USD',2,'principal');
CREATE TABLE openings (
    workspace TEXT NOT NULL, account_id TEXT NOT NULL, event_id TEXT NOT NULL,
    PRIMARY KEY (workspace,account_id),
    FOREIGN KEY (workspace,account_id) REFERENCES accounts(workspace,id),
    FOREIGN KEY (workspace,event_id) REFERENCES events(workspace,id)) STRICT;
INSERT INTO "openings" VALUES('019f0000-0000-7000-8000-000000000000','019f0000-0000-7000-8000-000000000001','019f0000-0000-7000-8000-000000000020');
CREATE TABLE receipts (
    workspace TEXT NOT NULL, operation_id TEXT NOT NULL, input TEXT NOT NULL,
    result_id TEXT NOT NULL, PRIMARY KEY(workspace,operation_id)) STRICT;
INSERT INTO "receipts" VALUES('019f0000-0000-7000-8000-000000000000','019f0000-0000-7000-8000-000000000010','["create-v1","019f0000-0000-7000-8000-000000000001",{"name":"Frozen fixture","kind":"bank","currency":"USD","scale":2,"openedOn":"2026-09-26","includeInNetWorth":true,"version":1,"state":"active","closedOn":null,"closingReason":null,"successorId":null},["posting-v1","opening","2026-09-26",["019f0000-0000-7000-8000-000000000001",1,{"version":1,"currency":"USD","scale":2,"minorUnits":"10000"},"principal"]]]','019f0000-0000-7000-8000-000000000020');
INSERT INTO "receipts" VALUES('019f0000-0000-7000-8000-000000000000','019f0000-0000-7000-8000-000000000011','["posting-v1","income","2026-09-26",["019f0000-0000-7000-8000-000000000001",1,{"version":1,"currency":"USD","scale":2,"minorUnits":"2000"},"principal"]]','019f0000-0000-7000-8000-000000000021');
INSERT INTO "receipts" VALUES('019f0000-0000-7000-8000-000000000000','019f0000-0000-7000-8000-000000000012','["posting-v1","expense","2026-09-26",["019f0000-0000-7000-8000-000000000001",1,{"version":1,"currency":"USD","scale":2,"minorUnits":"-500"},"principal"]]','019f0000-0000-7000-8000-000000000022');
COMMIT;
PRAGMA user_version = 1;
