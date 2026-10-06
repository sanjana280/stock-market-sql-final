-- Safe regression checks for a seeded database. Every successful data change is rolled back at the end.
-- Run after 01_schema, 03_indexes, 05_functions, 06_procedures, 07_triggers, 02_seed_data, and 04_views.
BEGIN;

-- Expected validation failures are caught and reported; an unexpected success fails the script.
DO $$
DECLARE v_portfolio BIGINT; v_stock BIGINT; v_held NUMERIC;
BEGIN
 SELECT portfolio_id,stock_id,quantity INTO v_portfolio,v_stock,v_held FROM holdings ORDER BY portfolio_id,stock_id LIMIT 1;
 IF v_portfolio IS NULL THEN RAISE EXCEPTION 'Tests require at least one seeded holding'; END IF;
 BEGIN
  CALL execute_trade(v_portfolio,v_stock,'HOLD',1,100,0,now());
  RAISE EXCEPTION 'Test failed: invalid trade type was accepted' USING ERRCODE='P0001';
 EXCEPTION WHEN SQLSTATE '22023' THEN RAISE NOTICE 'PASS: invalid trade type rejected'; END;
 BEGIN
  CALL execute_trade(v_portfolio,v_stock,'BUY',-1,100,0,now());
  RAISE EXCEPTION 'Test failed: negative quantity was accepted' USING ERRCODE='P0001';
 EXCEPTION WHEN SQLSTATE '22023' THEN RAISE NOTICE 'PASS: negative quantity rejected'; END;
 BEGIN
  CALL execute_trade(v_portfolio,v_stock,'BUY',1,-100,0,now());
  RAISE EXCEPTION 'Test failed: negative price was accepted' USING ERRCODE='P0001';
 EXCEPTION WHEN SQLSTATE '22023' THEN RAISE NOTICE 'PASS: negative price rejected'; END;
 BEGIN
  CALL execute_trade(v_portfolio,v_stock,'SELL',v_held+1,100,0,now());
  RAISE EXCEPTION 'Test failed: oversell was accepted' USING ERRCODE='P0001';
 EXCEPTION WHEN SQLSTATE '23514' THEN RAISE NOTICE 'PASS: selling more shares than held rejected'; END;
END $$;

-- Exercise BUY, fee-aware average cost, SELL, rebalance, valuation, P&L and updated_at behavior.
DO $$
DECLARE v_portfolio BIGINT; v_stock BIGINT; v_qty NUMERIC; v_avg NUMERIC; v_after_qty NUMERIC; v_after_avg NUMERIC;
 v_expected NUMERIC; v_value NUMERIC; v_view_value NUMERIC; v_realized NUMERIC; v_expected_realized NUMERIC;
 v_old_updated TIMESTAMPTZ; v_new_updated TIMESTAMPTZ; v_cash_count BIGINT; v_actual_cash_count BIGINT;
BEGIN
 SELECT portfolio_id,stock_id,quantity,average_buy_price,updated_at INTO v_portfolio,v_stock,v_qty,v_avg,v_old_updated
 FROM holdings ORDER BY portfolio_id,stock_id LIMIT 1;
 SELECT count(*) INTO v_cash_count FROM cash_transactions WHERE portfolio_id=v_portfolio;
 CALL execute_trade(v_portfolio,v_stock,'BUY',2,100,2,now()+interval '1 minute');
 SELECT quantity,average_buy_price,updated_at INTO v_after_qty,v_after_avg,v_new_updated
 FROM holdings WHERE portfolio_id=v_portfolio AND stock_id=v_stock;
 v_expected:=round((v_qty*v_avg+202)/(v_qty+2),4);
 IF v_after_qty<>v_qty+2 OR v_after_avg<>v_expected THEN RAISE EXCEPTION 'BUY holding/weighted-average check failed'; END IF;
 IF v_new_updated<=v_old_updated THEN RAISE EXCEPTION 'updated_at trigger did not advance'; END IF;
 SELECT count(*) INTO v_actual_cash_count FROM cash_transactions WHERE portfolio_id=v_portfolio;
 IF v_actual_cash_count<>v_cash_count+1 THEN RAISE EXCEPTION 'BUY cash transaction trigger check failed'; END IF;
 RAISE NOTICE 'PASS: valid BUY updates quantity, fee-aware average cost and updated_at';

 CALL execute_trade(v_portfolio,v_stock,'SELL',1,110,1,now()+interval '2 minutes');
 SELECT quantity INTO v_after_qty FROM holdings WHERE portfolio_id=v_portfolio AND stock_id=v_stock;
 IF v_after_qty<>v_qty+1 THEN RAISE EXCEPTION 'SELL holding quantity check failed'; END IF;
 SELECT count(*) INTO v_actual_cash_count FROM cash_transactions WHERE portfolio_id=v_portfolio;
 IF v_actual_cash_count<>v_cash_count+2 THEN RAISE EXCEPTION 'SELL cash transaction trigger check failed'; END IF;
 RAISE NOTICE 'PASS: valid SELL reduces the open holding';

 CALL sp_rebalance_holding(v_portfolio,v_stock,v_qty+2,100,0,now()+interval '3 minutes');
 SELECT quantity INTO v_after_qty FROM holdings WHERE portfolio_id=v_portfolio AND stock_id=v_stock;
 IF v_after_qty<>v_qty+2 THEN RAISE EXCEPTION 'Rebalance target quantity check failed'; END IF;
 SELECT count(*) INTO v_actual_cash_count FROM cash_transactions WHERE portfolio_id=v_portfolio;
 IF v_actual_cash_count<>v_cash_count+3 THEN RAISE EXCEPTION 'Rebalance cash transaction check failed'; END IF;
 RAISE NOTICE 'PASS: rebalance procedure trades the delta to the target quantity';

 SELECT coalesce(sum(market_value),0) INTO v_view_value FROM current_portfolio_valuation WHERE portfolio_id=v_portfolio;
 v_value:=fn_portfolio_current_value(v_portfolio);
 IF v_value<>v_view_value THEN RAISE EXCEPTION 'Portfolio valuation function/view mismatch'; END IF;
 IF fn_portfolio_unrealized_pnl(v_portfolio) IS NULL THEN RAISE EXCEPTION 'Unrealized P&L must not be NULL'; END IF;
 RAISE NOTICE 'PASS: valuation and unrealized P&L calculations return consistent results';

 v_realized:=fn_portfolio_realized_pnl(v_portfolio);
 SELECT coalesce(sum(fn_realized_pnl(v_portfolio,x.stock_id)),0) INTO v_expected_realized
 FROM (SELECT DISTINCT stock_id FROM trades WHERE portfolio_id=v_portfolio) x;
 IF v_realized<>round(v_expected_realized,2) THEN RAISE EXCEPTION 'Realized P&L rollup mismatch'; END IF;
 IF NOT EXISTS (SELECT 1 FROM investor_pnl WHERE investor_id=(SELECT investor_id FROM portfolios WHERE portfolio_id=v_portfolio))
 THEN RAISE EXCEPTION 'Investor P&L view missing investor'; END IF;
 RAISE NOTICE 'PASS: realized P&L and investor P&L view are populated';
END $$;

-- All successful test trades, cash entries, and holding changes are intentionally discarded.
ROLLBACK;




