-- Re-runnable view rebuild. Drop dependent views first, without CASCADE, so no
-- unrelated objects are removed. All source tables and seed data are preserved.
DROP VIEW IF EXISTS investor_pnl;
DROP VIEW IF EXISTS sector_performance;
DROP VIEW IF EXISTS stock_performance;
DROP VIEW IF EXISTS v_monthly_trade_activity;
DROP VIEW IF EXISTS v_portfolio_summary;
DROP VIEW IF EXISTS v_portfolio_market_value;
DROP VIEW IF EXISTS current_portfolio_valuation;

-- 1. Base valuation: one row per open portfolio/stock holding.
-- Uses the actual holdings.average_buy_price column and the latest available close.
CREATE VIEW current_portfolio_valuation AS
SELECT
    h.portfolio_id,
    h.stock_id,
    s.ticker_symbol,
    s.company_name,
    h.quantity,
    h.average_buy_price,
    h.average_buy_price AS cost_basis_per_share,
    (h.quantity * h.average_buy_price)::numeric(16, 2) AS cost_basis,
    px.close_price AS latest_price,
    px.price_date AS price_as_of,
    (h.quantity * px.close_price)::numeric(16, 2) AS market_value,
    (h.quantity * (px.close_price - h.average_buy_price))::numeric(16, 2) AS unrealized_pnl
FROM holdings AS h
JOIN stocks AS s ON s.stock_id = h.stock_id
LEFT JOIN LATERAL (
    SELECT sp.close_price, sp.price_date
    FROM stock_prices AS sp
    WHERE sp.stock_id = h.stock_id
    ORDER BY sp.price_date DESC
    LIMIT 1
) AS px ON TRUE;

-- 2. Compatibility interface used by existing analytics/query files.
CREATE VIEW v_portfolio_market_value AS
SELECT
    portfolio_id,
    stock_id,
    ticker_symbol,
    company_name,
    quantity,
    average_buy_price,
    latest_price AS close_price,
    price_as_of,
    market_value,
    unrealized_pnl AS unrealized_gain_loss
FROM current_portfolio_valuation;

-- 3. Portfolio equity plus cash. Cash ledger amounts are positive; transaction
-- type determines whether each amount increases or decreases the cash balance.
CREATE VIEW v_portfolio_summary AS
WITH holding_totals AS (
    SELECT
        portfolio_id,
        SUM(market_value) AS market_value,
        SUM(unrealized_pnl) AS unrealized_gain_loss
    FROM current_portfolio_valuation
    GROUP BY portfolio_id
), cash_totals AS (
    SELECT
        portfolio_id,
        SUM(CASE
            WHEN transaction_type IN ('DEPOSIT', 'TRADE_SELL', 'DIVIDEND') THEN amount
            ELSE -amount
        END) AS cash_balance
    FROM cash_transactions
    GROUP BY portfolio_id
)
SELECT
    p.portfolio_id,
    p.investor_id,
    p.portfolio_name,
    COALESCE(ht.market_value, 0)::numeric(16, 2) AS market_value,
    COALESCE(ct.cash_balance, 0)::numeric(16, 2) AS cash_balance,
    (COALESCE(ht.market_value, 0) + COALESCE(ct.cash_balance, 0))::numeric(16, 2) AS total_value,
    COALESCE(ht.unrealized_gain_loss, 0)::numeric(16, 2) AS unrealized_gain_loss
FROM portfolios AS p
LEFT JOIN holding_totals AS ht ON ht.portfolio_id = p.portfolio_id
LEFT JOIN cash_totals AS ct ON ct.portfolio_id = p.portfolio_id;

-- 4. Investor-level realized and unrealized P&L and current account value.
CREATE VIEW investor_pnl AS
WITH realized_by_investor AS (
    SELECT
        p.investor_id,
        SUM(fn_realized_pnl(traded.portfolio_id, traded.stock_id)) AS realized_pnl
    FROM (
        SELECT DISTINCT portfolio_id, stock_id
        FROM trades
    ) AS traded
    JOIN portfolios AS p ON p.portfolio_id = traded.portfolio_id
    GROUP BY p.investor_id
), open_positions_by_investor AS (
    SELECT
        p.investor_id,
        SUM(v.cost_basis) AS open_cost_basis,
        SUM(v.unrealized_pnl) AS unrealized_pnl
    FROM current_portfolio_valuation AS v
    JOIN portfolios AS p ON p.portfolio_id = v.portfolio_id
    GROUP BY p.investor_id
), account_value_by_investor AS (
    SELECT investor_id, SUM(total_value) AS total_portfolio_value
    FROM v_portfolio_summary
    GROUP BY investor_id
)
SELECT
    i.investor_id,
    i.full_name,
    COALESCE(r.realized_pnl, 0)::numeric(16, 2) AS realized_pnl,
    COALESCE(o.unrealized_pnl, 0)::numeric(16, 2) AS unrealized_pnl,
    COALESCE(o.open_cost_basis, 0)::numeric(16, 2) AS current_open_cost_basis,
    COALESCE(a.total_portfolio_value, 0)::numeric(16, 2) AS total_portfolio_value
FROM investors AS i
LEFT JOIN realized_by_investor AS r ON r.investor_id = i.investor_id
LEFT JOIN open_positions_by_investor AS o ON o.investor_id = i.investor_id
LEFT JOIN account_value_by_investor AS a ON a.investor_id = i.investor_id;

-- 5. Price return over the available portion of the trailing year, latest price,
-- recent market volume, and aggregate investor trade activity by stock.
CREATE VIEW stock_performance AS
WITH price_summary AS (
    SELECT
        stock_id,
        MIN(price_date) FILTER (WHERE price_date >= CURRENT_DATE - 365) AS first_date,
        MAX(price_date) AS last_date,
        SUM(volume) FILTER (WHERE price_date >= CURRENT_DATE - 365) AS trailing_volume,
        AVG(volume) FILTER (WHERE price_date >= CURRENT_DATE - 30) AS avg_daily_volume_30
    FROM stock_prices
    GROUP BY stock_id
), trade_summary AS (
    SELECT
        stock_id,
        COUNT(*) AS trade_count,
        SUM(quantity) AS shares_traded,
        SUM(quantity * price_per_share) AS trade_notional
    FROM trades
    GROUP BY stock_id
)
SELECT
    s.stock_id,
    s.ticker_symbol,
    s.company_name,
    s.sector_id,
    sec.sector_name,
    ps.first_date,
    ps.last_date,
    start_price.close_price AS period_start_price,
    latest_price.close_price AS latest_price,
    ROUND(100 * (latest_price.close_price / NULLIF(start_price.close_price, 0) - 1), 2) AS price_return_pct,
    ps.trailing_volume,
    ps.avg_daily_volume_30,
    COALESCE(ts.trade_count, 0) AS trade_count,
    COALESCE(ts.shares_traded, 0) AS shares_traded,
    COALESCE(ts.trade_notional, 0)::numeric(18, 2) AS trade_notional
FROM stocks AS s
JOIN sectors AS sec ON sec.sector_id = s.sector_id
JOIN price_summary AS ps ON ps.stock_id = s.stock_id
JOIN stock_prices AS start_price
  ON start_price.stock_id = ps.stock_id
 AND start_price.price_date = ps.first_date
JOIN stock_prices AS latest_price
  ON latest_price.stock_id = ps.stock_id
 AND latest_price.price_date = ps.last_date
LEFT JOIN trade_summary AS ts ON ts.stock_id = s.stock_id;

-- 6. Equal-weighted average of stock returns within each sector plus activity totals.
CREATE VIEW sector_performance AS
SELECT
    sec.sector_id,
    sec.sector_name,
    ROUND(AVG(sp.price_return_pct), 2) AS avg_stock_return_pct,
    SUM(sp.trailing_volume) AS trailing_market_volume,
    SUM(sp.trade_count) AS trade_count,
    SUM(sp.shares_traded) AS shares_traded,
    SUM(sp.trade_notional)::numeric(18, 2) AS trade_notional
FROM sectors AS sec
LEFT JOIN stock_performance AS sp ON sp.sector_id = sec.sector_id
GROUP BY sec.sector_id, sec.sector_name;

-- 7. Monthly trade counts and financial activity by portfolio.
CREATE VIEW v_monthly_trade_activity AS
SELECT
    portfolio_id,
    DATE_TRUNC('month', trade_date)::date AS month,
    COUNT(*) AS trade_count,
    COUNT(*) FILTER (WHERE trade_type = 'BUY') AS buy_count,
    COUNT(*) FILTER (WHERE trade_type = 'SELL') AS sell_count,
    SUM(quantity * price_per_share) AS gross_notional,
    SUM(brokerage_fee) AS fees
FROM trades
GROUP BY portfolio_id, DATE_TRUNC('month', trade_date)::date;