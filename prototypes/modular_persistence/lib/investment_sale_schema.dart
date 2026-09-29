/// Schema 22 is opt-in. Purchases and their original lots stay immutable;
/// each sale records its complete ordered cost allocation as a separate fact.
const investmentSaleColumns = [
  'workspace',
  'sell_id',
  'operation_id',
  'event_id',
  'investment_account_id',
  'instrument_id',
  'broker_id',
  'funding_account_id',
  'sequence',
  'cost_method',
  'payload',
];

const investmentSaleAllocationColumns = [
  'workspace',
  'sell_id',
  'lot_id',
  'ordinal',
  'sold_quantity_units',
  'allocated_cost',
  'remaining_quantity_units',
  'remaining_cost',
  'prior_version',
];

const investmentSaleSchema = [
  '''CREATE TABLE investment_sales (
    workspace TEXT NOT NULL, sell_id TEXT NOT NULL,
    operation_id TEXT NOT NULL, event_id TEXT NOT NULL,
    investment_account_id TEXT NOT NULL, instrument_id TEXT NOT NULL,
    broker_id TEXT NOT NULL, funding_account_id TEXT NOT NULL,
    sequence INTEGER NOT NULL CHECK(sequence >= 1),
    cost_method TEXT NOT NULL CHECK(cost_method IN ('fifo','averageCost')),
    payload TEXT NOT NULL,
    PRIMARY KEY(workspace,sell_id), UNIQUE(workspace,operation_id),
    UNIQUE(workspace,event_id),
    UNIQUE(workspace,investment_account_id,instrument_id,sequence),
    UNIQUE(workspace,sell_id,investment_account_id,instrument_id),
    CHECK(sell_id != event_id),
    FOREIGN KEY(workspace,event_id) REFERENCES events(workspace,id),
    FOREIGN KEY(workspace,investment_account_id,broker_id,funding_account_id)
      REFERENCES investment_accounts(workspace,id,broker_id,funding_account_id),
    FOREIGN KEY(workspace,instrument_id)
      REFERENCES investment_instruments(workspace,id)
  ) STRICT''',
  '''CREATE TABLE investment_sale_allocations (
    workspace TEXT NOT NULL, sell_id TEXT NOT NULL, lot_id TEXT NOT NULL,
    ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
    sold_quantity_units TEXT NOT NULL, allocated_cost INTEGER NOT NULL CHECK(allocated_cost >= 0),
    remaining_quantity_units TEXT NOT NULL, remaining_cost INTEGER NOT NULL CHECK(remaining_cost >= 0),
    prior_version INTEGER NOT NULL CHECK(prior_version >= 1),
    PRIMARY KEY(workspace,sell_id,lot_id), UNIQUE(workspace,sell_id,ordinal),
    FOREIGN KEY(workspace,sell_id) REFERENCES investment_sales(workspace,sell_id),
    FOREIGN KEY(workspace,lot_id) REFERENCES investment_lots(workspace,lot_id)
  ) STRICT''',
];
