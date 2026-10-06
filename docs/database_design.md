# Database design notes

## Modeling choices

- All monetary and share quantities use `NUMERIC`; floating point is reserved for trigonometric generation expressions before values are rounded and inserted.
- Market prices use one row per stock and calendar date with a uniqueness constraint. Sample series include weekends to provide exactly 366 observations per ticker; this is a teaching simplification, not an exchange calendar.
- `trades` is the transaction ledger. `holdings` stores only positive open positions and its moving weighted-average cost changes on buys; sells reduce quantity without changing remaining unit cost. The unit cost is rounded to four decimal places.
- `cash_transactions` signs direction by transaction type and stores positive amounts. The portfolio cash balance is derived as deposits + sale proceeds + dividend credits - withdrawals - purchase outflows.
- The `execute_trade` procedure validates inputs, serializes portfolio order entry and checks cash/holdings before inserting. `sp_rebalance_holding` routes a target-quantity delta through that procedure. Triggers apply holdings and cash effects to inserted trades and reject oversells; direct inserts receive the same after-insert enforcement.
- BUY brokerage fees are capitalized in average cost; SELL fees reduce sale proceeds. A full liquidation resets the cost pool before any later buy. Realized P&L therefore uses a single moving weighted-average method, not FIFO/tax lots.
- The sample omits automatic dividend payment credits because a declared dividend requires eligibility/record-date ownership rules. Dividend analytics estimate income from declared per-share amounts and current holdings only.
- Posted trades should be treated as append-only. Production edits/deletes require reversal events, robust serialization/locking, and audit controls beyond this intermediate teaching scope.

## Integrity

Foreign keys protect ownership and reference data. Checks constrain profiles, trade/transaction types, positive prices/quantities and OHLC consistency. Unique keys prevent duplicate emails/tickers, repeated daily quotes, and duplicate investor-stock watch entries.

## Indexes

Additional indexes cover descending portfolio/stock trade history, stock-to-sector joins, reverse lookups from stock to holdings, popular watched symbols and cash ledger history. Existing unique indexes already cover ticker and relevant pair/date lookups.

## Analytical definitions

- Market value: open quantity multiplied by the latest available close.
- Unrealized gain/loss: open quantity multiplied by (latest close minus holdings weighted-average buy price).
- Cash balance: sum of deposits, sale proceeds and credited income minus withdrawals and purchase costs/fees.
- Daily return: close divided by previous close minus one.
- Annualized volatility: sample standard deviation of daily returns multiplied by square root of 252.
- Dividend yield: declared distributions over the trailing 365 days divided by latest close.



