/// Schema 24 records a forward split without creating a cash Ledger event.
/// Original purchase lots stay immutable; replay applies exact quantity changes.
const investmentSplitColumns = [
  'workspace',
  'split_id',
  'operation_id',
  'investment_account_id',
  'instrument_id',
  'broker_id',
  'effective_on',
  'sequence',
  'payload',
];

const investmentSplitLotColumns = [
  'workspace',
  'split_id',
  'lot_id',
  'ordinal',
  'before_quantity_units',
  'after_quantity_units',
  'unchanged_cost',
  'prior_version',
];

const investmentSplitSchema = [
  '''CREATE TABLE investment_splits (
    workspace TEXT NOT NULL, split_id TEXT NOT NULL,
    operation_id TEXT NOT NULL, investment_account_id TEXT NOT NULL,
    instrument_id TEXT NOT NULL, broker_id TEXT NOT NULL,
    effective_on TEXT NOT NULL, sequence INTEGER NOT NULL CHECK(sequence >= 1),
    payload TEXT NOT NULL,
    PRIMARY KEY(workspace,split_id), UNIQUE(workspace,operation_id),
    UNIQUE(workspace,investment_account_id,instrument_id,sequence),
    FOREIGN KEY(workspace,investment_account_id) REFERENCES investment_accounts(workspace,id),
    FOREIGN KEY(workspace,instrument_id) REFERENCES investment_instruments(workspace,id),
    FOREIGN KEY(workspace,broker_id) REFERENCES investment_brokers(workspace,id)
  ) STRICT''',
  '''CREATE TABLE investment_split_lots (
    workspace TEXT NOT NULL, split_id TEXT NOT NULL, lot_id TEXT NOT NULL,
    ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
    before_quantity_units TEXT NOT NULL, after_quantity_units TEXT NOT NULL,
    unchanged_cost INTEGER NOT NULL CHECK(unchanged_cost >= 0),
    prior_version INTEGER NOT NULL CHECK(prior_version >= 1),
    PRIMARY KEY(workspace,split_id,lot_id), UNIQUE(workspace,split_id,ordinal),
    FOREIGN KEY(workspace,split_id) REFERENCES investment_splits(workspace,split_id),
    FOREIGN KEY(workspace,lot_id) REFERENCES investment_lots(workspace,lot_id)
  ) STRICT''',
];
