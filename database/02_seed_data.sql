-- Deterministic educational dataset. Run after 07_triggers.sql so trades post positions and cash.
BEGIN;
INSERT INTO sectors(sector_name) VALUES
 ('Technology'),('Healthcare'),('Financials'),('Consumer Discretionary'),('Consumer Staples'),('Energy'),('Industrials');
INSERT INTO investors(full_name,email,date_joined,risk_profile)
SELECT (ARRAY['Aarav Sharma','Maya Patel','Noah Williams','Aisha Khan','Liam Chen','Sofia Garcia','Ethan Johnson','Ananya Rao','Oliver Smith','Isha Mehta'])[(g-1)%10+1] || ' ' || g,
 'investor'||lpad(g::text,3,'0')||'@example.edu',DATE '2021-01-01'+((g*13)%1700),
 (ARRAY['CONSERVATIVE','MODERATE','AGGRESSIVE'])[(g*7)%3+1]
FROM generate_series(1,100) g;
INSERT INTO stocks(ticker_symbol,company_name,sector_id,ipo_date) VALUES
 ('AAPL','Apple Inc.',1,'1980-12-12'),('MSFT','Microsoft Corporation',1,'1986-03-13'),('NVDA','NVIDIA Corporation',1,'1999-01-22'),('ORCL','Oracle Corporation',1,'1986-03-12'),('CRM','Salesforce Inc.',1,'2004-06-23'),('ADBE','Adobe Inc.',1,'1986-08-20'),
 ('JNJ','Johnson & Johnson',2,'1944-09-24'),('PFE','Pfizer Inc.',2,'1942-06-22'),('MRK','Merck & Co.',2,'1946-12-10'),('ABT','Abbott Laboratories',2,'1929-03-01'),('UNH','UnitedHealth Group',2,'1984-10-17'),
 ('JPM','JPMorgan Chase & Co.',3,'1969-01-02'),('BAC','Bank of America',3,'1978-11-01'),('GS','Goldman Sachs Group',3,'1999-05-04'),('V','Visa Inc.',3,'2008-03-19'),('MA','Mastercard Inc.',3,'2006-05-25'),
 ('AMZN','Amazon.com Inc.',4,'1997-05-15'),('TSLA','Tesla Inc.',4,'2010-06-29'),('HD','Home Depot Inc.',4,'1981-09-22'),('NKE','NIKE Inc.',4,'1980-12-02'),('MCD','McDonald''s Corporation',4,'1965-04-21'),
 ('WMT','Walmart Inc.',5,'1970-10-01'),('COST','Costco Wholesale',5,'1985-12-05'),('PG','Procter & Gamble',5,'1891-05-12'),('KO','Coca-Cola Company',5,'1919-09-05'),
 ('XOM','Exxon Mobil Corporation',6,'1920-03-01'),('CVX','Chevron Corporation',6,'1921-06-24'),('COP','ConocoPhillips',6,'2002-08-12'),
 ('CAT','Caterpillar Inc.',7,'1929-12-02'),('HON','Honeywell International',7,'1927-09-23'),('UPS','United Parcel Service',7,'1999-11-10'),('GE','GE Aerospace',7,'1892-01-01'),('DE','Deere & Company',7,'1958-01-02'),('LMT','Lockheed Martin',7,'1995-12-31'),('IBM','International Business Machines',1,'1915-11-11'),('INTC','Intel Corporation',1,'1971-10-13'),('CSCO','Cisco Systems',1,'1990-02-16'),('TMO','Thermo Fisher Scientific',2,'1980-03-17'),('C','Citigroup Inc.',3,'1986-07-01'),('DIS','Walt Disney Company',4,'1957-11-12');
-- Synthetic smooth trends plus cyclical movement; values are intentionally fictional.
INSERT INTO stock_prices(stock_id,price_date,open_price,high_price,low_price,close_price,volume)
SELECT s.stock_id,d::date,
 round((b*(1+0.00018*n+0.035*sin(n/27.0))*(1+0.004*sin((n+s.stock_id)/3.0)))::numeric,4),
 round((b*(1+0.00018*n+0.035*sin(n/27.0))*(1+0.009+0.004*sin((n+s.stock_id)/3.0)))::numeric,4),
 round((b*(1+0.00018*n+0.035*sin(n/27.0))*(1-0.009+0.004*sin((n+s.stock_id)/3.0)))::numeric,4),
 round((b*(1+0.00018*n+0.035*sin(n/27.0))*(1+0.004*sin((n+s.stock_id)/3.0)))::numeric,4),
 (500000+(s.stock_id*7919+n*3571)%18000000)::bigint
FROM stocks s CROSS JOIN generate_series(CURRENT_DATE-365,CURRENT_DATE,interval '1 day') d
CROSS JOIN LATERAL (SELECT 35+s.stock_id*11 AS b,(d::date-(CURRENT_DATE-365)) AS n) x;
INSERT INTO portfolios(investor_id,portfolio_name,created_at)
SELECT investor_id,'Core Portfolio',date_joined::timestamp FROM investors;
-- Seed deposits first; each portfolio receives enough cash to fund its opening inventory.
INSERT INTO cash_transactions(portfolio_id,transaction_type,amount,transaction_date)
SELECT portfolio_id,'DEPOSIT',250000.00,created_at FROM portfolios;
INSERT INTO watchlists(investor_id,stock_id,added_at)
SELECT i.investor_id,((i.investor_id*7+j*11-1)%40)+1,CURRENT_TIMESTAMP-((j*3)::text||' days')::interval
FROM investors i CROSS JOIN generate_series(1,5) j;
INSERT INTO dividends(stock_id,dividend_date,dividend_per_share)
SELECT s.stock_id,d::date,round((0.12+(s.stock_id%9)*0.035)::numeric,4)
FROM stocks s CROSS JOIN (VALUES(CURRENT_DATE-270),(CURRENT_DATE-90)) v(d)
WHERE s.stock_id%3<>0;
-- 1,200 buys across a broad, fixed pool of investor-stock pairs.
INSERT INTO trades(portfolio_id,stock_id,trade_type,quantity,price_per_share,trade_date,brokerage_fee)
SELECT ((g-1)%100)+1,((g*17-1)%40)+1,'BUY',30,
 (SELECT close_price FROM stock_prices sp WHERE sp.stock_id=((g*17-1)%40)+1 ORDER BY price_date DESC LIMIT 1)* (0.86+((g%25)*0.01)),
 now()-((1200-g)::text||' days')::interval,1.00
FROM generate_series(1,1200) g;
-- 1,800 sells (1-4 shares each) from the funded opening positions, never exceeding 30 shares.
INSERT INTO trades(portfolio_id,stock_id,trade_type,quantity,price_per_share,trade_date,brokerage_fee)
SELECT ((g*37-1)%1200 %100)+1,
 (((((g*37-1)%1200)+1)*17-1)%40)+1,'SELL',1+(g%4),
 (SELECT close_price FROM stock_prices sp WHERE sp.stock_id=((((((g*37-1)%1200)+1)*17-1)%40)+1) ORDER BY price_date DESC LIMIT 1)*(1.01+((g%17)*0.012)),
 now()-((1200-(((g*37-1)%1200)+1))::text||' days')::interval,1.00
FROM generate_series(1,1800) g;
-- Credit synthetic dividend cash for shares held on each payment date is omitted deliberately;
-- dividend analytics use declared distributions and current positions in query examples.
COMMIT;





