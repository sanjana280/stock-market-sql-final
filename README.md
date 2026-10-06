# Stock Market Portfolio & Trading Analytics

A PostgreSQL project for modeling a small portfolio and brokerage domain and analyzing its trade ledger, holdings, cash movements, and educational market data. It demonstrates relational design, transactional BUY/SELL processing, moving weighted-average P&L, and analytical SQL. It has no application layer and uses no live market feed.

## Key features

- Ten related tables with primary/foreign keys, uniqueness rules, and financial validation constraints.
- Stored procedures for validated trade entry and target-quantity rebalancing.
- Triggers that serialize portfolio trade writes and update holdings and the cash ledger atomically.
- Reusable valuation, investor P&L, stock performance, sector performance, and monthly activity views.
- SQL functions for latest prices, daily returns, portfolio values, and realized/unrealized P&L.
- 38 example analytical queries across basic, intermediate, and advanced SQL.
- Rollback-safe regression checks and a rollback-only transaction demonstration.

## Schema overview

| Tables | Purpose |
| --- | --- |
| `investors`, `portfolios` | Investor details and owned portfolios. |
| `sectors`, `stocks`, `stock_prices` | Sector classifications, listed symbols, and dated OHLC/volume observations. |
| `trades`, `holdings` | Canonical BUY/SELL history and trigger-maintained current open positions. |
| `cash_transactions` | Positive ledger amounts whose transaction type determines cash direction. |
| `dividends`, `watchlists` | Declared per-share distributions and investor-stock watch membership. |

See [docs/database_design.md](docs/database_design.md) for modeling and calculation notes. The seed script generates a synthetic educational dataset (100 investors, 7 sectors, 40 stocks, 366 calendar-day price rows per stock, 3,000 trades, and related cash, dividend, and watchlist records). The price series includes weekends and is not an exchange calendar.

## SQL and analytical capabilities

The project demonstrates joins including `LATERAL`, CTEs, subqueries, `EXISTS`, conditional aggregation, `FILTER`, set operations, constraints, indexes, views, PL/pgSQL functions and procedures, triggers, and ACID transactions. Window-function examples include `LAG`, `LEAD`, ranking, running totals, and rolling calculations.

Analysis includes portfolio and investor account values, open positions, price returns, volume, realized and unrealized P&L, monthly trade activity, sector allocation, dividend yield estimates, and rolling returns/volatility. The query files are examples to run individually after setup; `database/08_analytics.sql` contains a compact set of report queries.

## P&L methodology

The project uses moving weighted-average cost, not FIFO or LIFO.

- A BUY adds execution value and its brokerage fee to the position cost pool. The resulting per-share average is stored to four decimal places.
- A SELL realizes `quantity × (sale price − current average cost) − sell fee`. Remaining shares retain the same average cost; a full liquidation clears the position.
- Unrealized P&L is open quantity multiplied by latest available close minus average buy price.
- Market value is open quantity multiplied by latest available close. Portfolio account value is market value plus ledger cash; it is not a deposit-adjusted investment return.
- Displayed valuation and P&L amounts are rounded to cents. Stock price returns exclude dividends.

These are educational estimates, not tax-lot or tax-reporting calculations.

## PostgreSQL features used

PostgreSQL 15 or later is required. The scripts use identity columns, `NUMERIC`, check/unique/foreign-key constraints, `FILTER`, `LATERAL`, window functions, `generate_series`, PL/pgSQL, procedures, trigger functions, and explicit transactions.

## Setup with PostgreSQL and pgAdmin 4

Use a **new, empty database** for a fresh setup. The schema and seed scripts are not an upgrade or reset process. Do not run the schema or seed scripts against an existing database you want to preserve. No script in this project drops or recreates a database.

1. Install PostgreSQL 15+ and pgAdmin 4.
2. In pgAdmin, connect to your PostgreSQL server. Right-click **Databases → Create → Database**, give the new database a name such as `stock_market_analytics`, and save.
3. Select that database, open **Tools → Query Tool**, then use the open-file button to load each SQL file in the order below. Execute each file and check the Messages/Results pane for errors before proceeding.
4. You can also run the same files with `psql` from the project root, using `psql -d stock_market_analytics -v ON_ERROR_STOP=1 -f <file>` for each path below.

### Execution order

The order follows dependencies: schema first; indexes and callable functions/procedures next; triggers before seed trades so seed trade side effects populate holdings and cash; views after their source objects and the P&L function; then analytics and optional rollback-only demonstrations.

1. `database/01_schema.sql`
2. `database/03_indexes.sql`
3. `database/05_functions.sql`
4. `database/06_procedures.sql`
5. `database/07_triggers.sql`
6. `database/02_seed_data.sql`
7. `database/04_views.sql`
8. `database/08_analytics.sql` (report queries; optional to create/use the database)
9. `database/09_tests.sql` (rollback-only checks; run after seed and views)
10. `database/10_transaction_examples.sql` (rollback-only example; run after seed and functions)

Files in `queries/` are separate analytical examples. They do not create schema objects and can be run in any order after the setup steps that create the database objects and seed data. `08_analytics.sql` is also a query script, not a schema migration.

### Run analytical queries

In pgAdmin, open `queries/01_basic_queries.sql`, `queries/02_intermediate_queries.sql`, or `queries/03_advanced_queries.sql` in the Query Tool connected to the configured database and execute the file. Run them separately to inspect each result set. The same files can be run with `psql -d stock_market_analytics -f queries/01_basic_queries.sql` (substitute another query filename as needed).

### Run checks

Run `database/09_tests.sql` after setup. It checks validation failures, BUY/SELL and rebalance effects, fee-aware average cost, cash and holdings updates, valuation, P&L, and the investor P&L view. Successful test changes are enclosed in a transaction that ends with `ROLLBACK`; expected validation errors are caught and reported as notices. In pgAdmin, execute the entire file as one script so the transaction and final rollback both run.

## Transaction demonstration

`database/10_transaction_examples.sql` selects an existing seeded position, performs a BUY and SELL through `execute_trade`, and rolls the enclosing transaction back. Run the entire file after setup. It leaves the seeded data unchanged when it completes successfully. The commented section at the bottom shows the shape of a manually reviewed transaction; uncomment and use it only when you intend to commit a real change to your own database.

## Runtime validation status

**Runtime-tested locally in PostgreSQL/pgAdmin 4.** The project owner reports successful local runtime checks of the schema/tables, seed data, triggers, views, functions, analytical queries, P&L calculations, validation constraints, BUY/SELL trigger behavior, and transaction rollback behavior. This statement records the owner-provided validation status; it is not a claim that Codex executed PostgreSQL tests.

## Data and scope note

Market prices, volumes, and trade activity are educational/static synthetic seed data, not live market data or verified historical prices. Dividend rows are declarations; the project does not model eligibility dates or automatically credit dividend payments. This project is for learning and portfolio demonstration, not investment or tax advice.
