-- BASIC SQL — 8 business questions

-- B1. Which stocks had the highest reported trading volume on the latest price date?
-- Helps identify the most actively traded symbols in the latest sample snapshot.
SELECT s.ticker_symbol,s.company_name,p.price_date,p.volume
FROM stock_prices p JOIN stocks s USING(stock_id)
WHERE p.price_date=(SELECT max(price_date) FROM stock_prices)
ORDER BY p.volume DESC LIMIT 10;

-- B2. What is each investor's total portfolio value?
-- Includes investors without portfolios by using LEFT JOIN and zero-fill.
SELECT i.investor_id,i.full_name,coalesce(sum(ps.total_value),0)::numeric(16,2) total_portfolio_value
FROM investors i LEFT JOIN v_portfolio_summary ps USING(investor_id)
GROUP BY i.investor_id,i.full_name ORDER BY total_portfolio_value DESC;

-- B3. What is each investor's realized P&L across their portfolios?
-- Applies the project's weighted-average cost function per portfolio-stock pair.
WITH pairs AS (SELECT DISTINCT portfolio_id,stock_id FROM trades), pnl AS (
 SELECT p.investor_id,sum(fn_realized_pnl(x.portfolio_id,x.stock_id)) realized_pnl
 FROM pairs x JOIN portfolios p USING(portfolio_id) GROUP BY p.investor_id)
SELECT i.investor_id,i.full_name,coalesce(p.realized_pnl,0)::numeric(16,2) realized_pnl
FROM investors i LEFT JOIN pnl p USING(investor_id) ORDER BY realized_pnl DESC;

-- B4. What is each investor's unrealized P&L on currently open positions?
-- Rolls holding-level mark-to-market estimates up to investor level.
SELECT i.investor_id,i.full_name,coalesce(sum(v.unrealized_gain_loss),0)::numeric(16,2) unrealized_pnl
FROM investors i LEFT JOIN portfolios p USING(investor_id)
LEFT JOIN v_portfolio_market_value v USING(portfolio_id)
GROUP BY i.investor_id,i.full_name ORDER BY unrealized_pnl DESC;

-- B5. Which stocks generated the highest one-year price return?
-- Compares the earliest and latest available closes within the past year.
WITH bounds AS (SELECT stock_id,min(price_date) first_day,max(price_date) last_day FROM stock_prices WHERE price_date>=CURRENT_DATE-365 GROUP BY stock_id), px AS (
 SELECT b.stock_id,p_first.close_price first_close,p_last.close_price last_close
 FROM bounds b JOIN stock_prices p_first ON p_first.stock_id=b.stock_id AND p_first.price_date=b.first_day
 JOIN stock_prices p_last ON p_last.stock_id=b.stock_id AND p_last.price_date=b.last_day)
SELECT s.ticker_symbol,round(100*(p.last_close/p.first_close-1),2) return_pct
FROM px p JOIN stocks s USING(stock_id) ORDER BY return_pct DESC LIMIT 10;

-- B6. Which sector had the highest average one-year stock return?
-- Calculates one return per stock from its first and latest quote in the trailing-year window.
WITH starts AS (SELECT DISTINCT ON(stock_id) stock_id,close_price FROM stock_prices WHERE price_date>=CURRENT_DATE-365 ORDER BY stock_id,price_date),
ends AS (SELECT DISTINCT ON(stock_id) stock_id,close_price FROM stock_prices ORDER BY stock_id,price_date DESC),
stock_returns AS (SELECT s.sector_id,100*(e.close_price/st.close_price-1) return_pct
 FROM stocks s JOIN starts st USING(stock_id) JOIN ends e USING(stock_id))
SELECT sec.sector_name,round(avg(r.return_pct),2) average_stock_return_pct
FROM stock_returns r JOIN sectors sec USING(sector_id)
GROUP BY sec.sector_name ORDER BY average_stock_return_pct DESC;
-- B7. Who are the top investors by total account value?
-- Ranks investors using the portfolio summary's holdings plus cash value.
SELECT i.investor_id,i.full_name,sum(ps.total_value)::numeric(16,2) total_value
FROM investors i JOIN v_portfolio_summary ps USING(investor_id)
GROUP BY i.investor_id,i.full_name ORDER BY total_value DESC LIMIT 10;

-- B8. What was the market's reported monthly share volume by ticker?
-- Sums daily share volume by stock and calendar month.
SELECT s.ticker_symbol,date_trunc('month',p.price_date)::date month,sum(p.volume) monthly_share_volume
FROM stock_prices p JOIN stocks s USING(stock_id)
GROUP BY s.ticker_symbol,date_trunc('month',p.price_date)::date ORDER BY month,s.ticker_symbol;


