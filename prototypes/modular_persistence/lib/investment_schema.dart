/// Schema 21 opt-in investment facts. Ledger remains the cash authority;
/// these rows identify the acquired instrument and the one immutable lot.
const investmentTables = [
  'investment_brokers',
  'investment_accounts',
  'investment_instruments',
  'investment_buys',
  'investment_lots',
];

const investmentBrokerColumns = ['workspace', 'id', 'name'];
const investmentAccountColumns = [
  'workspace',
  'id',
  'broker_id',
  'funding_account_id',
  'name',
  'version',
];
const investmentInstrumentColumns = [
  'workspace',
  'id',
  'kind',
  'market_code',
  'symbol',
  'name',
  'currency',
  'scale',
];
const investmentBuyColumns = [
  'workspace',
  'buy_id',
  'operation_id',
  'event_id',
  'investment_account_id',
  'instrument_id',
  'broker_id',
  'funding_account_id',
  'payload',
];
const investmentLotColumns = [
  'workspace',
  'lot_id',
  'buy_id',
  'investment_account_id',
  'instrument_id',
  'payload',
];

const investmentSchema = [
  '''CREATE TABLE investment_brokers (
    workspace TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL,
    PRIMARY KEY(workspace,id)
  ) STRICT''',
  '''CREATE TABLE investment_accounts (
    workspace TEXT NOT NULL, id TEXT NOT NULL, broker_id TEXT NOT NULL,
    funding_account_id TEXT NOT NULL, name TEXT NOT NULL,
    version INTEGER NOT NULL CHECK(version >= 1),
    PRIMARY KEY(workspace,id),
    UNIQUE(workspace,id,broker_id,funding_account_id),
    FOREIGN KEY(workspace,broker_id) REFERENCES investment_brokers(workspace,id),
    FOREIGN KEY(workspace,funding_account_id) REFERENCES accounts(workspace,id)
  ) STRICT''',
  '''CREATE TABLE investment_instruments (
    workspace TEXT NOT NULL, id TEXT NOT NULL, kind TEXT NOT NULL
      CHECK(kind IN ('stock','etf')),
    market_code TEXT NOT NULL, symbol TEXT NOT NULL, name TEXT NOT NULL,
    currency TEXT NOT NULL, scale INTEGER NOT NULL CHECK(scale BETWEEN 0 AND 18),
    PRIMARY KEY(workspace,id), UNIQUE(workspace,market_code,symbol)
  ) STRICT''',
  '''CREATE TABLE investment_buys (
    workspace TEXT NOT NULL, buy_id TEXT NOT NULL, operation_id TEXT NOT NULL,
    event_id TEXT NOT NULL, investment_account_id TEXT NOT NULL,
    instrument_id TEXT NOT NULL, broker_id TEXT NOT NULL,
    funding_account_id TEXT NOT NULL, payload TEXT NOT NULL,
    PRIMARY KEY(workspace,buy_id), UNIQUE(workspace,operation_id),
    UNIQUE(workspace,event_id),
    UNIQUE(workspace,buy_id,investment_account_id,instrument_id),
    CHECK(buy_id != event_id AND buy_id != investment_account_id AND buy_id != instrument_id),
    FOREIGN KEY(workspace,event_id) REFERENCES events(workspace,id),
    FOREIGN KEY(workspace,investment_account_id,broker_id,funding_account_id)
      REFERENCES investment_accounts(workspace,id,broker_id,funding_account_id),
    FOREIGN KEY(workspace,instrument_id)
      REFERENCES investment_instruments(workspace,id)
  ) STRICT''',
  '''CREATE TABLE investment_lots (
    workspace TEXT NOT NULL, lot_id TEXT NOT NULL, buy_id TEXT NOT NULL,
    investment_account_id TEXT NOT NULL, instrument_id TEXT NOT NULL,
    payload TEXT NOT NULL,
    PRIMARY KEY(workspace,lot_id), UNIQUE(workspace,buy_id),
    CHECK(lot_id != buy_id AND lot_id != investment_account_id AND lot_id != instrument_id),
    FOREIGN KEY(workspace,buy_id,investment_account_id,instrument_id)
      REFERENCES investment_buys(workspace,buy_id,investment_account_id,instrument_id)
  ) STRICT''',
];
