-- Lock portfolio rows before a direct trade insert to serialize all portfolio ledger updates.
CREATE OR REPLACE FUNCTION trg_lock_trade_portfolio() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM 1 FROM portfolios WHERE portfolio_id=NEW.portfolio_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Portfolio % does not exist',NEW.portfolio_id USING ERRCODE='23503'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_lock_trade_portfolio BEFORE INSERT ON trades FOR EACH ROW EXECUTE FUNCTION trg_lock_trade_portfolio();

-- Keep current positive positions and cash ledger synchronized with every accepted trade.
-- BUY fees are included in weighted-average cost; SELL fees reduce proceeds.
CREATE OR REPLACE FUNCTION trg_apply_trade() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE h holdings%ROWTYPE;
BEGIN
 IF NEW.trade_type='BUY' THEN
  INSERT INTO holdings(portfolio_id,stock_id,quantity,average_buy_price)
  VALUES(NEW.portfolio_id,NEW.stock_id,NEW.quantity,((NEW.quantity*NEW.price_per_share)+NEW.brokerage_fee)/NEW.quantity)
  ON CONFLICT(portfolio_id,stock_id) DO UPDATE SET
   average_buy_price=((holdings.quantity*holdings.average_buy_price)+(EXCLUDED.quantity*EXCLUDED.average_buy_price))/(holdings.quantity+EXCLUDED.quantity),
   quantity=holdings.quantity+EXCLUDED.quantity,updated_at=clock_timestamp();
  INSERT INTO cash_transactions(portfolio_id,transaction_type,amount,transaction_date,trade_id)
  VALUES(NEW.portfolio_id,'TRADE_BUY',NEW.quantity*NEW.price_per_share+NEW.brokerage_fee,NEW.trade_date,NEW.trade_id);
 ELSE
  IF NEW.brokerage_fee>=NEW.quantity*NEW.price_per_share THEN RAISE EXCEPTION 'Sell proceeds must exceed brokerage fee' USING ERRCODE='23514'; END IF;
  SELECT * INTO h FROM holdings WHERE portfolio_id=NEW.portfolio_id AND stock_id=NEW.stock_id FOR UPDATE;
  IF NOT FOUND OR h.quantity<NEW.quantity THEN RAISE EXCEPTION 'Insufficient shares to sell' USING ERRCODE='23514'; END IF;
  IF h.quantity=NEW.quantity THEN DELETE FROM holdings WHERE holding_id=h.holding_id;
  ELSE UPDATE holdings SET quantity=quantity-NEW.quantity,updated_at=clock_timestamp() WHERE holding_id=h.holding_id; END IF;
  INSERT INTO cash_transactions(portfolio_id,transaction_type,amount,transaction_date,trade_id)
  VALUES(NEW.portfolio_id,'TRADE_SELL',NEW.quantity*NEW.price_per_share-NEW.brokerage_fee,NEW.trade_date,NEW.trade_id);
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_trade_updates_position AFTER INSERT ON trades FOR EACH ROW EXECUTE FUNCTION trg_apply_trade();

-- Centralize cash-balance validation and serialize withdrawals/manual ledger entries.
CREATE OR REPLACE FUNCTION trg_cash_balance_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_balance NUMERIC;
BEGIN
 PERFORM 1 FROM portfolios WHERE portfolio_id=NEW.portfolio_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Portfolio % does not exist',NEW.portfolio_id USING ERRCODE='23503'; END IF;
 IF NEW.transaction_type IN ('WITHDRAWAL','TRADE_BUY') THEN
  SELECT coalesce(sum(CASE WHEN transaction_type IN ('DEPOSIT','TRADE_SELL','DIVIDEND') THEN amount ELSE -amount END),0)
  INTO v_balance FROM cash_transactions WHERE portfolio_id=NEW.portfolio_id;
  IF v_balance<NEW.amount THEN RAISE EXCEPTION 'Insufficient cash balance'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_cash_balance_guard BEFORE INSERT ON cash_transactions FOR EACH ROW EXECUTE FUNCTION trg_cash_balance_guard();

-- Maintain modification time for the current-position cache.
CREATE OR REPLACE FUNCTION trg_set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at:=clock_timestamp(); RETURN NEW; END $$;
CREATE TRIGGER trg_holdings_updated_at BEFORE UPDATE ON holdings FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
