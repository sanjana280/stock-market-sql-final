-- Moving weighted-average cost P&L. BUY fees are capitalized into basis; SELL fees reduce realized proceeds.
-- A full liquidation clears the position basis; a later buy starts a new average-cost position.
CREATE OR REPLACE FUNCTION fn_realized_pnl(p_portfolio_id BIGINT,p_stock_id BIGINT)
RETURNS NUMERIC LANGUAGE plpgsql STABLE AS $$
DECLARE r RECORD; v_qty NUMERIC:=0; v_basis NUMERIC:=0; v_avg NUMERIC; v_realized NUMERIC:=0;
BEGIN
 FOR r IN SELECT trade_type,quantity,price_per_share,brokerage_fee FROM trades
          WHERE portfolio_id=p_portfolio_id AND stock_id=p_stock_id ORDER BY trade_date,trade_id LOOP
  IF r.trade_type='BUY' THEN
   v_avg:=round((v_basis+(r.quantity*r.price_per_share)+r.brokerage_fee)/(v_qty+r.quantity),4);
   v_qty:=v_qty+r.quantity;
   v_basis:=v_qty*v_avg;
  ELSE
   IF r.quantity>v_qty THEN RAISE EXCEPTION 'Trade history oversells portfolio %, stock %',p_portfolio_id,p_stock_id USING ERRCODE='23514'; END IF;
   v_avg:=v_basis/nullif(v_qty,0);
   v_realized:=v_realized+(r.quantity*(r.price_per_share-v_avg))-r.brokerage_fee;
   v_qty:=v_qty-r.quantity;
   IF v_qty=0 THEN v_basis:=0; ELSE v_basis:=v_avg*v_qty; END IF;
  END IF;
 END LOOP;
 RETURN round(v_realized,2);
END $$;

-- Daily close-to-close simple returns for a stock; the first observation is NULL. A missing stock ID returns no rows.
CREATE OR REPLACE FUNCTION fn_daily_returns(p_stock_id BIGINT)
RETURNS TABLE(price_date DATE,close_price NUMERIC,daily_return NUMERIC) LANGUAGE SQL STABLE AS $$
 SELECT sp.price_date,sp.close_price,sp.close_price/nullif(lag(sp.close_price) OVER(ORDER BY sp.price_date),0)-1
 FROM stock_prices sp WHERE sp.stock_id=p_stock_id ORDER BY sp.price_date;
$$;

-- Latest available close, NULL when a valid stock has no price observations.
CREATE OR REPLACE FUNCTION fn_latest_stock_price(p_stock_id BIGINT)
RETURNS NUMERIC LANGUAGE SQL STABLE AS $$
 SELECT close_price FROM stock_prices WHERE stock_id=p_stock_id ORDER BY price_date DESC LIMIT 1;
$$;

-- Current market value of all open holdings in a portfolio.
CREATE OR REPLACE FUNCTION fn_portfolio_current_value(p_portfolio_id BIGINT)
RETURNS NUMERIC LANGUAGE SQL STABLE AS $$
 SELECT coalesce(sum(round(h.quantity*px.close_price,2)),0)::numeric(16,2)
 FROM holdings h LEFT JOIN LATERAL (SELECT close_price FROM stock_prices sp WHERE sp.stock_id=h.stock_id ORDER BY price_date DESC LIMIT 1) px ON true
 WHERE h.portfolio_id=p_portfolio_id;
$$;

-- Realized P&L summed across the portfolio's traded stocks using fn_realized_pnl average-cost accounting.
CREATE OR REPLACE FUNCTION fn_portfolio_realized_pnl(p_portfolio_id BIGINT)
RETURNS NUMERIC LANGUAGE SQL STABLE AS $$
 SELECT coalesce(sum(fn_realized_pnl(p_portfolio_id,x.stock_id)),0)::numeric(16,2)
 FROM (SELECT DISTINCT stock_id FROM trades WHERE portfolio_id=p_portfolio_id) x;
$$;

-- Unrealized P&L across current open holdings at latest available prices.
CREATE OR REPLACE FUNCTION fn_portfolio_unrealized_pnl(p_portfolio_id BIGINT)
RETURNS NUMERIC LANGUAGE SQL STABLE AS $$
 SELECT coalesce(sum(round(h.quantity*(px.close_price-h.average_buy_price),2)),0)::numeric(16,2)
 FROM holdings h LEFT JOIN LATERAL (SELECT close_price FROM stock_prices sp WHERE sp.stock_id=h.stock_id ORDER BY price_date DESC LIMIT 1) px ON true
 WHERE h.portfolio_id=p_portfolio_id;
$$;




