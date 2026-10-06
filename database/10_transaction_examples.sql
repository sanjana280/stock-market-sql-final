-- Executable atomic BUY/SELL demonstration. Uses a seeded open position and rolls the demo back.
-- Any failure in either trade or its trigger work aborts the whole transaction.
BEGIN;
DO $$
DECLARE v_portfolio BIGINT; v_stock BIGINT; v_available NUMERIC; v_price NUMERIC;
BEGIN
 SELECT h.portfolio_id,h.stock_id INTO v_portfolio,v_stock
 FROM holdings h ORDER BY h.portfolio_id,h.stock_id LIMIT 1;
 IF v_portfolio IS NULL THEN RAISE EXCEPTION 'Run this example after seeding the database'; END IF;
 SELECT coalesce(sum(CASE WHEN transaction_type IN ('DEPOSIT','TRADE_SELL','DIVIDEND') THEN amount ELSE -amount END),0)
 INTO v_available FROM cash_transactions WHERE portfolio_id=v_portfolio;
 SELECT fn_latest_stock_price(v_stock) INTO v_price;
 IF v_available < v_price+1 THEN RAISE EXCEPTION 'Selected portfolio lacks cash for demonstration buy'; END IF;
 CALL execute_trade(v_portfolio,v_stock,'BUY',1,v_price,1,now());
 CALL execute_trade(v_portfolio,v_stock,'SELL',1,v_price+1,1,now()+interval '1 second');
 RAISE NOTICE 'Both trades and trigger side-effects succeeded atomically; rolling back demonstration.';
END $$;
ROLLBACK;

-- For a real approved order, execute within an explicit transaction and commit only after review:
-- BEGIN;
-- CALL execute_trade(1,1,'BUY',2,150.00,1.00,now());
-- SELECT * FROM v_portfolio_summary WHERE portfolio_id=1;
-- COMMIT;
-- If any validation fails, PostgreSQL aborts the transaction; issue ROLLBACK before retrying.
