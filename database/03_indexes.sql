-- Unique constraints already index tickers, portfolio/investor names, holdings pairs, price dates, dividends, watches and trade-linked cash rows.
-- Descending date indexes support recent ledger reads and latest market observations.
CREATE INDEX IF NOT EXISTS idx_trades_portfolio_date ON trades(portfolio_id,trade_date DESC);
CREATE INDEX IF NOT EXISTS idx_trades_stock_date ON trades(stock_id,trade_date DESC);
-- Supports stock-to-sector joins and sector performance rollups.
CREATE INDEX IF NOT EXISTS idx_stocks_sector ON stocks(sector_id);
-- Reverse lookup for stock exposure across portfolios; the unique pair index starts with portfolio_id.
CREATE INDEX IF NOT EXISTS idx_holdings_stock ON holdings(stock_id);
-- Supports finding popular watchlist symbols; unique pair index starts with investor_id.
CREATE INDEX IF NOT EXISTS idx_watchlists_stock ON watchlists(stock_id);
-- Supports account cash ledger statements ordered newest-first.
CREATE INDEX IF NOT EXISTS idx_cash_portfolio_date ON cash_transactions(portfolio_id,transaction_date DESC);
