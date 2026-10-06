-- INTERMEDIATE SQL — 12 business questions

-- I1. What is the best-performing stock in each sector over the available year?
-- Ranks one-year price return within each sector.
WITH starts AS (SELECT DISTINCT ON(stock_id) stock_id,close_price FROM stock_prices WHERE price_date>=CURRENT_DATE-365 ORDER BY stock_id,price_date),
ends AS (SELECT DISTINCT ON(stock_id) stock_id,close_price FROM stock_prices ORDER BY stock_id,price_date DESC), returns AS (
 SELECT s.stock_id,s.ticker_symbol,sec.sector_name,100*(e.close_price/st.close_price-1) return_pct
 FROM stocks s JOIN sectors sec USING(sector_id) JOIN starts st USING(stock_id) JOIN ends e USING(stock_id)), ranked AS (
 SELECT *,row_number() OVER(PARTITION BY sector_name ORDER BY return_pct DESC) sector_pick FROM returns)
SELECT sector_name,ticker_symbol,round(return_pct,2) return_pct FROM ranked WHERE sector_pick=1 ORDER BY sector_name;

-- I2. Which investors have the most diversified portfolios?
-- Counts distinct open positions across each investor's accounts.
SELECT i.investor_id,i.full_name,count(DISTINCT h.stock_id) distinct_open_positions
FROM investors i LEFT JOIN portfolios p USING(investor_id) LEFT JOIN holdings h USING(portfolio_id)
GROUP BY i.investor_id,i.full_name ORDER BY distinct_open_positions DESC,i.investor_id;

-- I3. Which investors have highly concentrated portfolios?
-- Measures each investor's largest position as a percentage of their invested market value.
WITH positions AS (SELECT p.investor_id,v.market_value,sum(v.market_value) OVER(PARTITION BY p.investor_id) equity_value
 FROM v_portfolio_market_value v JOIN portfolios p USING(portfolio_id))
SELECT i.investor_id,i.full_name,round(100*max(x.market_value)/nullif(max(x.equity_value),0),2) largest_position_pct
FROM investors i JOIN positions x USING(investor_id) GROUP BY i.investor_id,i.full_name
HAVING max(x.equity_value)>0 ORDER BY largest_position_pct DESC;

-- I4. What is the monthly trading volume in shares and dollars?
-- Uses trade records rather than market-wide quote volume.
SELECT date_trunc('month',trade_date)::date month,trade_type,sum(quantity) shares_traded,
 round(sum(quantity*price_per_share),2) notional
FROM trades GROUP BY 1,trade_type ORDER BY 1,trade_type;

-- I5. What is the month-over-month closing-price change for each stock?
-- Compares each month's last close with the previous month's last close.
WITH month_ends AS (SELECT DISTINCT ON(stock_id,date_trunc('month',price_date)) stock_id,date_trunc('month',price_date)::date month,close_price
 FROM stock_prices ORDER BY stock_id,date_trunc('month',price_date),price_date DESC), changes AS (
 SELECT *,lag(close_price) OVER(PARTITION BY stock_id ORDER BY month) prior_month_close FROM month_ends)
SELECT s.ticker_symbol,c.month,c.close_price,c.prior_month_close,
 round(100*(c.close_price/nullif(c.prior_month_close,0)-1),2) mom_change_pct
FROM changes c JOIN stocks s USING(stock_id) ORDER BY s.ticker_symbol,c.month;

-- I6. What are the top five stocks by return in each month?
-- ROW_NUMBER resets per month to return at most five securities for each month.
WITH month_ends AS (SELECT DISTINCT ON(stock_id,date_trunc('month',price_date)) stock_id,date_trunc('month',price_date)::date month,close_price
 FROM stock_prices ORDER BY stock_id,date_trunc('month',price_date),price_date DESC), monthly AS (
 SELECT *,lag(close_price) OVER(PARTITION BY stock_id ORDER BY month) prior_close FROM month_ends), ranked AS (
 SELECT m.*,row_number() OVER(PARTITION BY month ORDER BY close_price/nullif(prior_close,0)-1 DESC) monthly_rank
 FROM monthly m WHERE prior_close IS NOT NULL)
SELECT r.month,s.ticker_symbol,round(100*(r.close_price/r.prior_close-1),2) monthly_return_pct,r.monthly_rank
FROM ranked r JOIN stocks s USING(stock_id) WHERE monthly_rank<=5 ORDER BY month,monthly_rank;

-- I7. What is each investor's largest open holding?
-- Returns a single largest position per investor, with deterministic ticker tie-breaking.
WITH ranked AS (SELECT p.investor_id,v.ticker_symbol,v.market_value,
 row_number() OVER(PARTITION BY p.investor_id ORDER BY v.market_value DESC,v.ticker_symbol) position_no
 FROM v_portfolio_market_value v JOIN portfolios p USING(portfolio_id))
SELECT i.full_name,r.ticker_symbol,r.market_value FROM ranked r JOIN investors i USING(investor_id)
WHERE position_no=1 ORDER BY r.market_value DESC;

-- I8. Which stocks show declining trading volume?
-- Compares average market volume over the latest 30 observations to the prior 30.
WITH ordered AS (SELECT stock_id,price_date,volume,row_number() OVER(PARTITION BY stock_id ORDER BY price_date DESC) newest_first FROM stock_prices), windows AS (
 SELECT stock_id,avg(volume) FILTER(WHERE newest_first<=30) recent_avg,
 avg(volume) FILTER(WHERE newest_first BETWEEN 31 AND 60) prior_avg FROM ordered GROUP BY stock_id)
SELECT s.ticker_symbol,round(w.recent_avg,0) recent_avg_volume,round(w.prior_avg,0) prior_avg_volume
FROM windows w JOIN stocks s USING(stock_id) WHERE w.recent_avg<w.prior_avg ORDER BY w.recent_avg/w.prior_avg;

-- I9. Which investors have not traded in the last 90 days?
-- Uses NOT EXISTS to include investors with no trade history at all.
SELECT i.investor_id,i.full_name FROM investors i
WHERE NOT EXISTS (SELECT 1 FROM portfolios p JOIN trades t USING(portfolio_id)
 WHERE p.investor_id=i.investor_id AND t.trade_date>=now()-interval '90 days') ORDER BY i.investor_id;

-- I10. What is the average buy price for each currently open holding?
-- Compares maintained average cost with the current market mark.
SELECT p.portfolio_id,i.full_name,v.ticker_symbol,v.quantity,v.average_buy_price,v.close_price,
 round(v.close_price-v.average_buy_price,2) price_difference
FROM v_portfolio_market_value v JOIN portfolios p USING(portfolio_id) JOIN investors i USING(investor_id)
ORDER BY i.full_name,v.ticker_symbol;

-- I11. Which portfolio-stock positions generated the largest realized gains?
-- Reuses the canonical fee-aware moving weighted-average P&L function instead of estimating lots independently.
WITH pairs AS (SELECT DISTINCT portfolio_id,stock_id FROM trades), realized AS (
 SELECT portfolio_id,stock_id,fn_realized_pnl(portfolio_id,stock_id) realized_pnl FROM pairs)
SELECT i.full_name,p.portfolio_name,s.ticker_symbol,r.realized_pnl
FROM realized r JOIN portfolios p USING(portfolio_id) JOIN investors i USING(investor_id) JOIN stocks s USING(stock_id)
WHERE r.realized_pnl>0 ORDER BY r.realized_pnl DESC LIMIT 25;
-- I12. What percentage of each portfolio is invested in each sector?
-- Aggregates market value by sector and normalizes within each portfolio.
WITH sector_values AS (SELECT v.portfolio_id,s.sector_id,sec.sector_name,sum(v.market_value) sector_value
 FROM v_portfolio_market_value v JOIN stocks s USING(stock_id) JOIN sectors sec USING(sector_id)
 GROUP BY v.portfolio_id,s.sector_id,sec.sector_name)
SELECT portfolio_id,sector_name,round(100*sector_value/nullif(sum(sector_value) OVER(PARTITION BY portfolio_id),0),2) portfolio_weight_pct
FROM sector_values ORDER BY portfolio_id,portfolio_weight_pct DESC;

