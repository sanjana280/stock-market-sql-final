-- Core analytics. Run after 01_schema, 03_indexes, 05_functions, 06_procedures, 07_triggers, 02_seed_data, and 04_views.
-- 1. Highest-value portfolios
SELECT investor_id,portfolio_name,market_value,cash_balance,total_value FROM v_portfolio_summary ORDER BY total_value DESC LIMIT 10;

-- 2. Sector diversification by current market value
SELECT sec.sector_name,round(sum(v.market_value),2) market_value,
 round(100*sum(v.market_value)/nullif(sum(sum(v.market_value)) OVER(),0),2) pct_of_equity
FROM v_portfolio_market_value v JOIN stocks s USING(stock_id) JOIN sectors sec USING(sector_id)
GROUP BY sec.sector_name ORDER BY market_value DESC;

-- 3. Realized P&L using weighted average historical buy cost (example portfolio / stock)
SELECT fn_realized_pnl(1,1) AS realized_pnl;

-- 4. Rolling 30-price-observation return and volatility per stock
WITH r AS (SELECT stock_id,price_date,close_price/lag(close_price) OVER(PARTITION BY stock_id ORDER BY price_date)-1 daily_return FROM stock_prices)
SELECT stock_id,price_date,round((exp(sum(ln(1+daily_return)) OVER(PARTITION BY stock_id ORDER BY price_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW)-1)*100)::numeric,2) rolling_30_observation_return_pct,
 round((stddev_samp(daily_return) OVER(PARTITION BY stock_id ORDER BY price_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW)*sqrt(252)*100)::numeric,2) annualized_volatility_pct
FROM r WHERE daily_return IS NOT NULL;

-- 5. Monthly trade activity
SELECT * FROM v_monthly_trade_activity ORDER BY month DESC, gross_notional DESC;

-- 6. Dividend yield (trailing 365-day declared dividends / latest close)
SELECT s.ticker_symbol,round(100*sum(d.dividend_per_share)/p.close_price,2) trailing_yield_pct
FROM stocks s JOIN dividends d USING(stock_id)
JOIN LATERAL (SELECT close_price FROM stock_prices WHERE stock_id=s.stock_id ORDER BY price_date DESC LIMIT 1) p ON true
WHERE d.dividend_date>=CURRENT_DATE-365 GROUP BY s.ticker_symbol,p.close_price ORDER BY trailing_yield_pct DESC;

-- New reusable portfolio and market performance views/functions
SELECT * FROM investor_pnl ORDER BY total_portfolio_value DESC LIMIT 10;
SELECT * FROM sector_performance ORDER BY avg_stock_return_pct DESC;
SELECT fn_latest_stock_price(1) AS latest_close,
       fn_portfolio_current_value(1) AS current_equity_value,
       fn_portfolio_realized_pnl(1) AS realized_pnl,
       fn_portfolio_unrealized_pnl(1) AS unrealized_pnl;

