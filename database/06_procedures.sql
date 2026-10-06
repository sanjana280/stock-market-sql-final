-- Validated, serialized trade entry. Trigger trg_trade_updates_position is the sole holdings/cash updater.
CREATE OR REPLACE PROCEDURE execute_trade(
 IN p_portfolio_id BIGINT,IN p_stock_id BIGINT,IN p_trade_type TEXT,IN p_quantity NUMERIC,
 IN p_price_per_share NUMERIC,IN p_brokerage_fee NUMERIC,IN p_trade_date TIMESTAMPTZ DEFAULT now())
LANGUAGE plpgsql AS $$
DECLARE v_cash NUMERIC; v_held NUMERIC; v_trade_id BIGINT;
BEGIN
 IF p_trade_type IS NULL OR p_trade_type NOT IN ('BUY','SELL') THEN RAISE EXCEPTION 'Trade type must be BUY or SELL' USING ERRCODE='22023'; END IF;
 IF p_quantity IS NULL OR p_quantity<=0 THEN RAISE EXCEPTION 'Quantity must be positive' USING ERRCODE='22023'; END IF;
 IF p_price_per_share IS NULL OR p_price_per_share<=0 THEN RAISE EXCEPTION 'Price must be positive' USING ERRCODE='22023'; END IF;
 IF p_brokerage_fee IS NULL OR p_brokerage_fee<0 THEN RAISE EXCEPTION 'Brokerage fee cannot be negative' USING ERRCODE='22023'; END IF;
 IF p_trade_date IS NULL THEN RAISE EXCEPTION 'Trade date is required' USING ERRCODE='22023'; END IF;
 PERFORM 1 FROM portfolios WHERE portfolio_id=p_portfolio_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Portfolio % does not exist',p_portfolio_id USING ERRCODE='23503'; END IF;
 PERFORM 1 FROM stocks WHERE stock_id=p_stock_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Stock % does not exist',p_stock_id USING ERRCODE='23503'; END IF;
 SELECT coalesce(sum(CASE WHEN transaction_type IN ('DEPOSIT','TRADE_SELL','DIVIDEND') THEN amount ELSE -amount END),0)
 INTO v_cash FROM cash_transactions WHERE portfolio_id=p_portfolio_id;
 IF p_trade_type='BUY' AND v_cash < p_quantity*p_price_per_share+p_brokerage_fee THEN
  RAISE EXCEPTION 'Insufficient cash: available %, required %',v_cash,p_quantity*p_price_per_share+p_brokerage_fee USING ERRCODE='23514';
 END IF;
 IF p_trade_type='SELL' THEN
  SELECT quantity INTO v_held FROM holdings WHERE portfolio_id=p_portfolio_id AND stock_id=p_stock_id FOR UPDATE;
  IF NOT FOUND OR v_held<p_quantity THEN RAISE EXCEPTION 'Insufficient shares to sell' USING ERRCODE='23514'; END IF;
  IF p_brokerage_fee>=p_quantity*p_price_per_share THEN RAISE EXCEPTION 'Sell proceeds must exceed brokerage fee' USING ERRCODE='23514'; END IF;
 END IF;
 INSERT INTO trades(portfolio_id,stock_id,trade_type,quantity,price_per_share,trade_date,brokerage_fee)
 VALUES(p_portfolio_id,p_stock_id,p_trade_type,p_quantity,p_price_per_share,p_trade_date,p_brokerage_fee)
 RETURNING trade_id INTO v_trade_id;
END $$;

-- Reconcile one position to a target share quantity, recording only the required BUY or SELL delta.
-- Price and fee are supplied by the caller to keep the database independent of an execution venue.
CREATE OR REPLACE PROCEDURE sp_rebalance_holding(
 IN p_portfolio_id BIGINT,IN p_stock_id BIGINT,IN p_target_quantity NUMERIC,
 IN p_execution_price NUMERIC,IN p_brokerage_fee NUMERIC DEFAULT 0,IN p_trade_date TIMESTAMPTZ DEFAULT now())
LANGUAGE plpgsql AS $$
DECLARE v_current NUMERIC; v_delta NUMERIC;
BEGIN
 IF p_target_quantity IS NULL OR p_target_quantity<0 THEN RAISE EXCEPTION 'Target quantity must be non-negative' USING ERRCODE='22023'; END IF;
 IF p_execution_price IS NULL OR p_execution_price<=0 OR p_brokerage_fee IS NULL OR p_brokerage_fee<0 THEN
  RAISE EXCEPTION 'Execution price must be positive and fee non-negative' USING ERRCODE='22023';
 END IF;
 PERFORM 1 FROM portfolios WHERE portfolio_id=p_portfolio_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Portfolio % does not exist',p_portfolio_id USING ERRCODE='23503'; END IF;
 PERFORM 1 FROM stocks WHERE stock_id=p_stock_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Stock % does not exist',p_stock_id USING ERRCODE='23503'; END IF;
 SELECT quantity INTO v_current FROM holdings WHERE portfolio_id=p_portfolio_id AND stock_id=p_stock_id FOR UPDATE;
 v_current:=coalesce(v_current,0);
 v_delta:=p_target_quantity-v_current;
 IF v_delta>0 THEN
  CALL execute_trade(p_portfolio_id,p_stock_id,'BUY',v_delta,p_execution_price,p_brokerage_fee,p_trade_date);
 ELSIF v_delta<0 THEN
  CALL execute_trade(p_portfolio_id,p_stock_id,'SELL',abs(v_delta),p_execution_price,p_brokerage_fee,p_trade_date);
 END IF;
END $$;
