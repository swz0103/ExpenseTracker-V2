/// Schema 23 adds immutable broker-reported cash dividends. The Ledger event
/// remains the sole cash authority and each dividend owns one event/receipt.
const investmentDividendColumns = [
  'workspace',
  'dividend_id',
  'operation_id',
  'event_id',
  'investment_account_id',
  'instrument_id',
  'broker_id',
  'funding_account_id',
  'payload',
];

const investmentDividendSchema = '''CREATE TABLE investment_dividends (
  workspace TEXT NOT NULL, dividend_id TEXT NOT NULL,
  operation_id TEXT NOT NULL, event_id TEXT NOT NULL,
  investment_account_id TEXT NOT NULL, instrument_id TEXT NOT NULL,
  broker_id TEXT NOT NULL, funding_account_id TEXT NOT NULL,
  payload TEXT NOT NULL,
  PRIMARY KEY(workspace,dividend_id), UNIQUE(workspace,operation_id),
  UNIQUE(workspace,event_id), CHECK(dividend_id != event_id),
  FOREIGN KEY(workspace,event_id) REFERENCES events(workspace,id),
  FOREIGN KEY(workspace,investment_account_id,broker_id,funding_account_id)
    REFERENCES investment_accounts(workspace,id,broker_id,funding_account_id),
  FOREIGN KEY(workspace,instrument_id)
    REFERENCES investment_instruments(workspace,id)
) STRICT''';
