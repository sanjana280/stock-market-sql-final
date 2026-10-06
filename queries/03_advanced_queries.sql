-- ADVANCED SQL — 18 business questions

-- A1. What is the cumulative daily notional traded per stock?
-- A running total exposes changes in activity over time.
SELECT s.ticker_symbol,t.trade_date::date trade_day,
 sum(t.quantity*t.price_per_share) daily_notional,
 sum(sum(t.quantity*t.price_per_share)) OVER(PARTITION BY t.stock_id ORDER BY t.trade_date::date ROWS UNBOUNDED PRECEDING) running_notional
FROM trades t JOIN stocks s USING(stock_id) GROUP BY s.ticker_symbol,t.stock_id,t.trade_date::date ORDER BY s.ticker_symbol,trade_day;

-- A2. What is the 20-observation moving average close and its deviation from price?
-- Window frames calculate a rolling benchmark independently for each stock.
WITH avg_px AS (SELECT stock_id,price_date,close_price,avg(close_price) OVER(PARTITION BY stock_id ORDER BY price_date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) ma20 FROM stock_prices)
SELECT s.ticker_symbol,a.price_date,a.close_price,round(a.ma20,2) moving_average_20,
 round(100*(a.close_price/a.ma20-1),2) deviation_pct FROM avg_px a JOIN stocks s USING(stock_id)
WHERE a.price_date>=CURRENT_DATE-30 ORDER BY s.ticker_symbol,a.price_date;

-- A3. Which stocks rose for three consecutive price observations?
-- LAG checks the last two closes and confirms each row is an advancing observation.
WITH x AS (SELECT stock_id,price_date,close_price,
 lag(close_price,1) OVER(PARTITION BY stock_id ORDER BY price_date) prev1,
 lag(close_price,2) OVER(PARTITION BY stock_id ORDER BY price_date) prev2,
 lag(price_date,1) OVER(PARTITION BY stock_id ORDER BY price_date) date1,
 lag(price_date,2) OVER(PARTITION BY stock_id ORDER BY price_date) date2 FROM stock_prices)
SELECT s.ticker_symbol,x.price_date,x.prev2,x.prev1,x.close_price FROM x JOIN stocks s USING(stock_id)
WHERE x.close_price>x.prev1 AND x.prev1>x.prev2 AND x.price_date=x.date1+1 AND x.date1=x.date2+1 ORDER BY x.price_date,s.ticker_symbol;

-- A4. What was each stock's latest available close?
-- ROW_NUMBER selects exactly one latest record per ticker.
WITH ranked AS (SELECT stock_id,price_date,close_price,row_number() OVER(PARTITION BY stock_id ORDER BY price_date DESC) rn FROM stock_prices)
SELECT s.ticker_symbol,r.price_date,r.close_price FROM ranked r JOIN stocks s USING(stock_id) WHERE rn=1 ORDER BY s.ticker_symbol;

-- A5. How do investors rank within their stated risk profile by account value?
-- RANK preserves ties and restarts for each profile.
SELECT i.risk_profile,i.full_name,sum(ps.total_value)::numeric(16,2) total_value,
 rank() OVER(PARTITION BY i.risk_profile ORDER BY sum(ps.total_value) DESC) profile_rank
FROM investors i JOIN v_portfolio_summary ps USING(investor_id) GROUP BY i.risk_profile,i.investor_id,i.full_name
ORDER BY i.risk_profile,profile_rank;

-- A6. Which sectors rank highest by average annualized stock return?
-- DENSE_RANK gives tied sectors the same rank without gaps.
WITH annual AS (SELECT DISTINCT ON(stock_id) stock_id,close_price FROM stock_prices ORDER BY stock_id,price_date DESC),
initial AS (SELECT DISTINCT ON(stock_id) stock_id,close_price FROM stock_prices WHERE price_date<=CURRENT_DATE-365 ORDER BY stock_id,price_date DESC),
sector_returns AS (SELECT sec.sector_name,avg(a.close_price/i.close_price-1) avg_return FROM annual a JOIN initial i USING(stock_id) JOIN stocks s USING(stock_id) JOIN sectors sec USING(sector_id) GROUP BY sec.sector_name)
SELECT sector_name,round(100*avg_return,2) average_return_pct,dense_rank() OVER(ORDER BY avg_return DESC) sector_rank
FROM sector_returns ORDER BY sector_rank,sector_name;

-- A7. What is the next observed closing price for every stock date?
-- LEAD supports next-observation comparisons and return labels.
WITH observed AS (SELECT stock_id,price_date,close_price,
 lead(close_price) OVER(PARTITION BY stock_id ORDER BY price_date) next_observation_close FROM stock_prices)
SELECT s.ticker_symbol,o.price_date,o.close_price,o.next_observation_close
FROM observed o JOIN stocks s USING(stock_id) WHERE o.price_date>=CURRENT_DATE-7 ORDER BY s.ticker_symbol,o.price_date;

-- A8. How does monthly market-wide quote volume compare with the prior month?
-- Aggregates then uses LAG over the resulting month series.
WITH monthly AS (SELECT date_trunc('month',price_date)::date month,sum(volume) share_volume FROM stock_prices GROUP BY 1)
SELECT month,share_volume,lag(share_volume) OVER(ORDER BY month) prior_month_volume,
 round(100*(share_volume/nullif(lag(share_volume) OVER(ORDER BY month),0)-1),2) change_pct FROM monthly ORDER BY month;

-- A9. Which open positions belong to stocks that have declared dividends?
-- EXISTS tests declaration presence without multiplying a holding by multiple dividend rows.
SELECT p.portfolio_id,i.full_name,v.ticker_symbol,v.quantity FROM v_portfolio_market_value v
JOIN portfolios p USING(portfolio_id) JOIN investors i USING(investor_id)
WHERE EXISTS (SELECT 1 FROM dividends d WHERE d.stock_id=v.stock_id) ORDER BY p.portfolio_id,v.ticker_symbol;

-- A10. Which portfolios have funded cash but no current open positions?
-- NOT EXISTS avoids false matches caused by outer joins across unrelated rows.
SELECT p.portfolio_id,p.portfolio_name,coalesce(sum(CASE WHEN c.transaction_type IN ('DEPOSIT','TRADE_SELL','DIVIDEND') THEN c.amount ELSE -c.amount END),0) cash_balance
FROM portfolios p LEFT JOIN cash_transactions c USING(portfolio_id)
WHERE NOT EXISTS (SELECT 1 FROM holdings h WHERE h.portfolio_id=p.portfolio_id)
GROUP BY p.portfolio_id,p.portfolio_name HAVING coalesce(sum(CASE WHEN c.transaction_type IN ('DEPOSIT','TRADE_SELL','DIVIDEND') THEN c.amount ELSE -c.amount END),0)>0;

-- A11. How can each position be classified by gain/loss and size?
-- CASE translates numeric exposure into readable business segments.
SELECT portfolio_id,ticker_symbol,market_value,unrealized_gain_loss,
 CASE WHEN unrealized_gain_loss>0 THEN 'GAIN' WHEN unrealized_gain_loss<0 THEN 'LOSS' ELSE 'BREAK_EVEN' END pnl_status,
 CASE WHEN market_value>=10000 THEN 'LARGE' WHEN market_value>=2500 THEN 'MEDIUM' ELSE 'SMALL' END position_size
FROM v_portfolio_market_value ORDER BY portfolio_id,market_value DESC;

-- A12. What is each portfolio's buy/sell mix and average order size?
-- Conditional aggregation produces side-by-side business metrics in one row.
SELECT portfolio_id,count(*) total_trades,
 count(*) FILTER(WHERE trade_type='BUY') buy_trades,count(*) FILTER(WHERE trade_type='SELL') sell_trades,
 round(avg(quantity) FILTER(WHERE trade_type='BUY'),2) avg_buy_shares,
 round(avg(quantity) FILTER(WHERE trade_type='SELL'),2) avg_sell_shares
FROM trades GROUP BY portfolio_id ORDER BY portfolio_id;

-- A13. Which stocks have a latest close above their own historical average?
-- Correlated subquery compares each ticker's latest observation with its own mean.
SELECT s.ticker_symbol,p.price_date,p.close_price FROM stocks s JOIN stock_prices p USING(stock_id)
WHERE p.price_date=(SELECT max(p2.price_date) FROM stock_prices p2 WHERE p2.stock_id=s.stock_id)
AND p.close_price>(SELECT avg(p3.close_price) FROM stock_prices p3 WHERE p3.stock_id=s.stock_id)
ORDER BY p.close_price-(SELECT avg(p4.close_price) FROM stock_prices p4 WHERE p4.stock_id=s.stock_id) DESC;

-- A14. Which portfolios have positive realized P&L but negative unrealized P&L?
-- A CTE separates historical closed-trade results from current open-mark results.
WITH closed AS (SELECT DISTINCT portfolio_id,stock_id FROM trades), realized AS (
 SELECT portfolio_id,sum(fn_realized_pnl(portfolio_id,stock_id)) realized_pnl FROM closed GROUP BY portfolio_id),
 open_pnl AS (SELECT portfolio_id,sum(unrealized_gain_loss) unrealized_pnl FROM v_portfolio_market_value GROUP BY portfolio_id)
SELECT p.portfolio_id,p.portfolio_name,coalesce(r.realized_pnl,0)::numeric(16,2) realized_pnl,coalesce(o.unrealized_pnl,0)::numeric(16,2) unrealized_pnl
FROM portfolios p LEFT JOIN realized r USING(portfolio_id) LEFT JOIN open_pnl o USING(portfolio_id)
WHERE coalesce(r.realized_pnl,0)>0 AND coalesce(o.unrealized_pnl,0)<0 ORDER BY realized_pnl DESC;

-- A15. Which stocks have been added to watchlists but never traded by any investor?
-- UNION builds a combined activity set; membership filters isolate watch-only symbols.
WITH watched AS (SELECT stock_id FROM watchlists), traded AS (SELECT stock_id FROM trades),
 activity AS (SELECT stock_id,'WATCHED' activity FROM watched UNION SELECT stock_id,'TRADED' FROM traded)
SELECT s.ticker_symbol,s.company_name FROM stocks s
WHERE s.stock_id IN (SELECT stock_id FROM activity WHERE activity='WATCHED')
AND s.stock_id NOT IN (SELECT stock_id FROM activity WHERE activity='TRADED') ORDER BY s.ticker_symbol;

-- A16. How do 30-observation returns and annualized volatility compare across stocks?
-- Rolling windows partition each stock and use log returns for compounded performance.
WITH r AS (SELECT stock_id,price_date,close_price/lag(close_price) OVER(PARTITION BY stock_id ORDER BY price_date)-1 daily_return FROM stock_prices),
 m AS (SELECT stock_id,price_date,
 exp(sum(ln(1+daily_return)) OVER(PARTITION BY stock_id ORDER BY price_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW))-1 rolling_return,
 stddev_samp(daily_return) OVER(PARTITION BY stock_id ORDER BY price_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW)*sqrt(252) annualized_vol
 FROM r WHERE daily_return IS NOT NULL)
SELECT s.ticker_symbol,m.price_date,round(100*m.rolling_return,2) return_30obs_pct,round(100*m.annualized_vol,2) volatility_pct
FROM m JOIN stocks s USING(stock_id) WHERE m.price_date>=CURRENT_DATE-30 ORDER BY m.price_date,s.ticker_symbol;

-- A17. Which investors generated the greatest brokerage costs as a share of traded notional?
-- Joins investor, portfolio and trade facts and aggregates the fee ratio.
SELECT i.investor_id,i.full_name,sum(t.brokerage_fee) fees,
 round(100*sum(t.brokerage_fee)/nullif(sum(t.quantity*t.price_per_share),0),3) fee_rate_pct
FROM investors i JOIN portfolios p USING(investor_id) JOIN trades t USING(portfolio_id)
GROUP BY i.investor_id,i.full_name HAVING sum(t.quantity*t.price_per_share)>0 ORDER BY fee_rate_pct DESC;

-- A18. How many investors fall into total-value bands?
-- UNION ALL combines mutually exclusive CASE-based categories while retaining every investor once.
WITH investor_values AS (SELECT i.investor_id,coalesce(sum(ps.total_value),0) total_value
 FROM investors i LEFT JOIN v_portfolio_summary ps USING(investor_id) GROUP BY i.investor_id), bands AS (
 SELECT investor_id,CASE WHEN total_value>=100000 THEN '100K_PLUS' WHEN total_value>=50000 THEN '50K_TO_100K' ELSE 'UNDER_50K' END band FROM investor_values)
SELECT 'UNDER_50K' value_band,count(*) investor_count FROM bands WHERE band='UNDER_50K'
UNION ALL SELECT '50K_TO_100K',count(*) FROM bands WHERE band='50K_TO_100K'
UNION ALL SELECT '100K_PLUS',count(*) FROM bands WHERE band='100K_PLUS' ORDER BY value_band;



