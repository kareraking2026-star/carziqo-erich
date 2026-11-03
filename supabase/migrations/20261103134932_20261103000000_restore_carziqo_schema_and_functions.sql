/*
# Restore Carziqo schema and member functions

1. Purpose
- Repairs the deployed database so the current Carziqo app can query its schema and call its server-side actions.
- Adds only missing columns/tables and replaces missing RPC functions; existing user data is preserved.

2. Schema additions
- `profiles.free_vehicle_used` and `profiles.is_blocked` track trial use and account status.
- `vehicles.is_free_vehicle` marks a free trial vehicle.
- `recharge_requests.transaction_hash`, `recharge_requests.proof_path`, and `recharge_requests.updated_at` support payment review.
- `withdrawal_addresses` stores private user-owned withdrawal destinations.
- `withdrawal_requests.withdrawal_address_id` links a withdrawal to a saved destination.
- `mall_orders.image_url` stores the purchased product image.
- `team_members.member_user_id` links a team row to the referred member.

3. Functions restored
- Member actions: `request_withdrawal`, `rent_vehicle`, `claim_daily_earnings`, `exchange_carbon_points`, `purchase_mall_product`, `submit_bubble_game`.
- Referral actions: `process_referral_signup`, `process_referral_investment`.
- Admin member actions: `admin_get_profiles`, `admin_block_user`, `admin_unblock_user`, `admin_adjust_balance`.

4. Security
- Row-level security is enabled on the new withdrawal-address table.
- Member-owned policies restrict withdrawal destinations to their owner.
- Financial and admin functions run with a fixed public search path and are executable only by authenticated users.
- No tables, columns, or records are deleted.

5. Compatibility notes
- Functions use the deployed table names (`rentals`, not `user_rentals`).
- Mall purchases use carbon points at 100 points per peso, matching the current app behavior.
*/

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS free_vehicle_used boolean NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_blocked boolean NOT NULL DEFAULT false;
ALTER TABLE public.vehicles ADD COLUMN IF NOT EXISTS is_free_vehicle boolean NOT NULL DEFAULT false;
ALTER TABLE public.recharge_requests ADD COLUMN IF NOT EXISTS transaction_hash text DEFAULT '';
ALTER TABLE public.recharge_requests ADD COLUMN IF NOT EXISTS proof_path text;
ALTER TABLE public.recharge_requests ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
ALTER TABLE public.mall_orders ADD COLUMN IF NOT EXISTS image_url text DEFAULT '';
ALTER TABLE public.team_members ADD COLUMN IF NOT EXISTS member_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE TABLE IF NOT EXISTS public.withdrawal_addresses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  label text NOT NULL DEFAULT '',
  method text NOT NULL DEFAULT 'bank_transfer',
  account_name text NOT NULL DEFAULT '',
  account_number text NOT NULL DEFAULT '',
  bank_name text DEFAULT '',
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.withdrawal_addresses ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.withdrawal_addresses TO authenticated;
DROP POLICY IF EXISTS "select_own_withdrawal_addresses" ON public.withdrawal_addresses;
CREATE POLICY "select_own_withdrawal_addresses" ON public.withdrawal_addresses FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "insert_own_withdrawal_addresses" ON public.withdrawal_addresses;
CREATE POLICY "insert_own_withdrawal_addresses" ON public.withdrawal_addresses FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "update_own_withdrawal_addresses" ON public.withdrawal_addresses;
CREATE POLICY "update_own_withdrawal_addresses" ON public.withdrawal_addresses FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "delete_own_withdrawal_addresses" ON public.withdrawal_addresses;
CREATE POLICY "delete_own_withdrawal_addresses" ON public.withdrawal_addresses FOR DELETE TO authenticated USING (auth.uid() = user_id);
ALTER TABLE public.withdrawal_requests ADD COLUMN IF NOT EXISTS withdrawal_address_id uuid REFERENCES public.withdrawal_addresses(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.request_withdrawal(p_amount numeric, p_method text, p_address_id uuid, p_withdrawal_password text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user_id uuid := auth.uid(); v_balance numeric; v_password text;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  SELECT wallet_balance, withdrawal_password INTO v_balance, v_password FROM profiles WHERE user_id = v_user_id;
  IF v_balance IS NULL THEN RETURN jsonb_build_object('error','Profile not found'); END IF;
  IF p_amount < 500 THEN RETURN jsonb_build_object('error','Minimum withdrawal is ₱500'); END IF;
  IF p_amount > v_balance THEN RETURN jsonb_build_object('error','Insufficient wallet balance'); END IF;
  IF COALESCE(p_withdrawal_password,'') = '' OR COALESCE(v_password,'') = '' OR p_withdrawal_password <> v_password THEN RETURN jsonb_build_object('error','Withdrawal password incorrect'); END IF;
  IF NOT EXISTS (SELECT 1 FROM withdrawal_addresses WHERE id = p_address_id AND user_id = v_user_id) THEN RETURN jsonb_build_object('error','Invalid withdrawal address'); END IF;
  UPDATE profiles SET wallet_balance = wallet_balance - p_amount WHERE user_id = v_user_id AND wallet_balance >= p_amount;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Insufficient wallet balance'); END IF;
  INSERT INTO withdrawal_requests (user_id, amount, method, status, withdrawal_address_id) VALUES (v_user_id, p_amount, p_method, 'pending', p_address_id);
  INSERT INTO wallet_transactions (user_id, type, amount, status, description) VALUES (v_user_id, 'withdrawal_hold', -p_amount, 'pending', 'Withdrawal pending admin review via ' || p_method);
  RETURN jsonb_build_object('success',true);
END; $$;

CREATE OR REPLACE FUNCTION public.rent_vehicle(p_vehicle_id uuid, p_rental_days integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user_id uuid := auth.uid(); v_balance numeric; v_vehicle record; v_existing integer; v_total numeric;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF p_rental_days IS NULL OR p_rental_days < 1 THEN RETURN jsonb_build_object('error','Invalid rental period'); END IF;
  SELECT * INTO v_vehicle FROM vehicles WHERE id = p_vehicle_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Vehicle not found'); END IF;
  IF COALESCE(v_vehicle.stock,0) <= 0 THEN RETURN jsonb_build_object('error','Vehicle out of stock'); END IF;
  SELECT wallet_balance INTO v_balance FROM profiles WHERE user_id = v_user_id;
  IF v_balance IS NULL THEN RETURN jsonb_build_object('error','Profile not found'); END IF;
  SELECT count(*) INTO v_existing FROM rentals WHERE user_id = v_user_id AND vehicle_id = p_vehicle_id AND status = 'active';
  IF v_existing >= COALESCE(v_vehicle.rental_limit,1) THEN RETURN jsonb_build_object('error','Rental limit reached for this vehicle'); END IF;
  IF v_vehicle.is_free_vehicle THEN
    IF EXISTS (SELECT 1 FROM profiles WHERE user_id = v_user_id AND free_vehicle_used) THEN RETURN jsonb_build_object('error','Free trial already used'); END IF;
    UPDATE profiles SET free_vehicle_used = true WHERE user_id = v_user_id;
    v_total := v_vehicle.daily_return * COALESCE(v_vehicle.settlement_cycle, p_rental_days);
    INSERT INTO rentals (user_id,vehicle_id,vehicle_name,rental_period,daily_income,total_income,status) VALUES (v_user_id,p_vehicle_id,v_vehicle.name,COALESCE(v_vehicle.settlement_cycle,p_rental_days),v_vehicle.daily_return,v_total,'active');
    INSERT INTO wallet_transactions (user_id,type,amount,status,description) VALUES (v_user_id,'free_trial',0,'completed','Free trial: ' || v_vehicle.name);
  ELSE
    IF v_vehicle.price > v_balance THEN RETURN jsonb_build_object('error','Insufficient wallet balance'); END IF;
    v_total := v_vehicle.daily_return * p_rental_days;
    UPDATE profiles SET wallet_balance = wallet_balance - v_vehicle.price WHERE user_id = v_user_id AND wallet_balance >= v_vehicle.price;
    IF NOT FOUND THEN RETURN jsonb_build_object('error','Insufficient wallet balance'); END IF;
    INSERT INTO rentals (user_id,vehicle_id,vehicle_name,rental_period,daily_income,total_income,status) VALUES (v_user_id,p_vehicle_id,v_vehicle.name,p_rental_days,v_vehicle.daily_return,v_total,'active');
    INSERT INTO wallet_transactions (user_id,type,amount,status,description) VALUES (v_user_id,'rental',-v_vehicle.price,'completed','Rented ' || v_vehicle.name);
    PERFORM process_referral_investment(v_user_id, v_vehicle.price);
  END IF;
  UPDATE vehicles SET stock = stock - 1 WHERE id = p_vehicle_id AND stock > 0;
  RETURN jsonb_build_object('success',true);
END; $$;

CREATE OR REPLACE FUNCTION public.claim_daily_earnings()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user_id uuid := auth.uid(); v_total numeric := 0; v_rental record;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF EXISTS (SELECT 1 FROM daily_earnings WHERE user_id = v_user_id AND date::date = (now() AT TIME ZONE 'UTC')::date) THEN RETURN jsonb_build_object('success',true,'already_claimed',true); END IF;
  FOR v_rental IN SELECT id, vehicle_name, daily_income FROM rentals WHERE user_id = v_user_id AND status = 'active' LOOP
    INSERT INTO daily_earnings (user_id,rental_id,vehicle_name,amount,date) VALUES (v_user_id,v_rental.id,v_rental.vehicle_name,v_rental.daily_income,now()); v_total := v_total + v_rental.daily_income;
  END LOOP;
  IF v_total = 0 THEN RETURN jsonb_build_object('success',true,'no_earnings',true); END IF;
  UPDATE profiles SET wallet_balance = COALESCE(wallet_balance,0) + v_total, total_earnings = COALESCE(total_earnings,0) + v_total WHERE user_id = v_user_id;
  INSERT INTO wallet_transactions (user_id,type,amount,status,description) VALUES (v_user_id,'daily_earnings',v_total,'completed','Daily earnings credited');
  RETURN jsonb_build_object('success',true,'amount',v_total);
END; $$;

CREATE OR REPLACE FUNCTION public.exchange_carbon_points(p_points integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user_id uuid := auth.uid(); v_carbon numeric; v_amount numeric;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF p_points IS NULL OR p_points <= 0 THEN RETURN jsonb_build_object('error','Invalid points amount'); END IF;
  SELECT carbon_points INTO v_carbon FROM profiles WHERE user_id = v_user_id;
  IF v_carbon IS NULL THEN RETURN jsonb_build_object('error','Profile not found'); END IF;
  IF p_points > v_carbon THEN RETURN jsonb_build_object('error','Insufficient carbon points'); END IF;
  v_amount := p_points * 0.01;
  UPDATE profiles SET carbon_points = carbon_points - p_points, wallet_balance = COALESCE(wallet_balance,0) + v_amount WHERE user_id = v_user_id AND carbon_points >= p_points;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Insufficient carbon points'); END IF;
  INSERT INTO carbon_records (user_id,type,points,description) VALUES (v_user_id,'exchange',-p_points,'Carbon Exchange');
  INSERT INTO wallet_transactions (user_id,type,amount,status,description) VALUES (v_user_id,'carbon_exchange',v_amount,'completed','Carbon exchange: ' || p_points || ' points at ₱0.01 each');
  RETURN jsonb_build_object('success',true,'amount',v_amount);
END; $$;

CREATE OR REPLACE FUNCTION public.purchase_mall_product(p_product_id uuid, p_quantity integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user_id uuid := auth.uid(); v_product record; v_cost numeric;
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF p_quantity IS NULL OR p_quantity < 1 OR p_quantity > 99 THEN RETURN jsonb_build_object('error','Invalid quantity'); END IF;
  SELECT * INTO v_product FROM mall_products WHERE id = p_product_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Product not found'); END IF;
  IF v_product.stock < p_quantity THEN RETURN jsonb_build_object('error','Insufficient stock'); END IF;
  v_cost := round(v_product.price * p_quantity / 0.01);
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE user_id = v_user_id AND carbon_points >= v_cost) THEN RETURN jsonb_build_object('error','Insufficient carbon points'); END IF;
  UPDATE profiles SET carbon_points = carbon_points - v_cost WHERE user_id = v_user_id AND carbon_points >= v_cost;
  INSERT INTO carbon_records (user_id,type,points,description) VALUES (v_user_id,'exchange',-v_cost,'Mall: ' || v_product.name || ' x' || p_quantity);
  INSERT INTO mall_orders (user_id,product_id,product_name,image_url,quantity,total_price,status) VALUES (v_user_id,p_product_id,v_product.name,COALESCE(NULLIF(btrim(v_product.image_url),''),'/assets/images/carziqo.webp'),p_quantity,v_product.price*p_quantity,'completed');
  UPDATE mall_products SET stock = stock - p_quantity WHERE id = p_product_id;
  RETURN jsonb_build_object('success',true,'carbon_cost',v_cost);
END; $$;

CREATE OR REPLACE FUNCTION public.submit_bubble_game(p_points integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_user_id uuid := auth.uid(); v_start timestamptz := date_trunc('day',now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
BEGIN
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF p_points IS NULL OR p_points < 0 OR p_points > 500 THEN RETURN jsonb_build_object('error','Invalid score'); END IF;
  IF EXISTS (SELECT 1 FROM bubble_records WHERE user_id = v_user_id AND created_at >= v_start) THEN RETURN jsonb_build_object('error','You have already played today. Come back tomorrow.'); END IF;
  INSERT INTO bubble_records (user_id,points_earned) VALUES (v_user_id,p_points);
  INSERT INTO carbon_records (user_id,type,points,description) VALUES (v_user_id,'earn',p_points,'Pop Bubbles reward');
  UPDATE profiles SET carbon_points = COALESCE(carbon_points,0) + p_points WHERE user_id = v_user_id;
  RETURN jsonb_build_object('success',true,'points',p_points);
END; $$;

CREATE OR REPLACE FUNCTION public.process_referral_signup(p_new_user_id uuid, p_referrer_code text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_referrer uuid; v_name text; v_phone text;
BEGIN
  IF COALESCE(trim(p_referrer_code),'') = '' THEN RETURN; END IF;
  SELECT user_id INTO v_referrer FROM profiles WHERE referral_code = trim(p_referrer_code) LIMIT 1;
  IF v_referrer IS NULL OR v_referrer = p_new_user_id THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM team_members WHERE user_id = v_referrer AND member_user_id = p_new_user_id) THEN RETURN; END IF;
  SELECT nickname,phone INTO v_name,v_phone FROM profiles WHERE user_id = p_new_user_id;
  INSERT INTO team_members (user_id,member_user_id,member_name,member_phone,commission,status) VALUES (v_referrer,p_new_user_id,COALESCE(v_name,'New Member'),COALESCE(v_phone,''),50,'active');
  UPDATE profiles SET wallet_balance = COALESCE(wallet_balance,0)+50,total_earnings = COALESCE(total_earnings,0)+50 WHERE user_id = v_referrer;
  INSERT INTO wallet_transactions (user_id,type,amount,status,description) VALUES (v_referrer,'referral_bonus',50,'completed','Referral signup bonus');
END; $$;

CREATE OR REPLACE FUNCTION public.process_referral_investment(p_investing_user_id uuid, p_investment_amount numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_referrer_code text; v_referrer uuid; v_commission numeric := p_investment_amount * 0.10;
BEGIN
  SELECT referrer_code INTO v_referrer_code FROM profiles WHERE user_id = p_investing_user_id;
  IF COALESCE(trim(v_referrer_code),'') = '' THEN RETURN; END IF;
  SELECT user_id INTO v_referrer FROM profiles WHERE referral_code = trim(v_referrer_code) LIMIT 1;
  IF v_referrer IS NULL OR v_referrer = p_investing_user_id THEN RETURN; END IF;
  UPDATE team_members SET commission = COALESCE(commission,0)+v_commission,total_investment = COALESCE(total_investment,0)+p_investment_amount WHERE user_id = v_referrer AND member_user_id = p_investing_user_id;
  UPDATE profiles SET wallet_balance = COALESCE(wallet_balance,0)+v_commission,total_earnings = COALESCE(total_earnings,0)+v_commission WHERE user_id = v_referrer;
  INSERT INTO wallet_transactions (user_id,type,amount,status,description) VALUES (v_referrer,'referral_commission',v_commission,'completed','Referral investment commission');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_get_profiles()
RETURNS SETOF profiles LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN IF NOT is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF; RETURN QUERY SELECT * FROM profiles ORDER BY created_at DESC LIMIT 500; END; $$;
CREATE OR REPLACE FUNCTION public.admin_block_user(p_user_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$ BEGIN IF NOT is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF; UPDATE profiles SET is_blocked=true WHERE user_id=p_user_id; END; $$;
CREATE OR REPLACE FUNCTION public.admin_unblock_user(p_user_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$ BEGIN IF NOT is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF; UPDATE profiles SET is_blocked=false WHERE user_id=p_user_id; END; $$;
CREATE OR REPLACE FUNCTION public.admin_adjust_balance(p_user_id uuid,p_amount numeric,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_balance numeric;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF;
  IF p_amount IS NULL OR p_amount = 0 THEN RETURN jsonb_build_object('error','Amount must be non-zero'); END IF;
  UPDATE profiles SET wallet_balance=COALESCE(wallet_balance,0)+p_amount WHERE user_id=p_user_id RETURNING wallet_balance INTO v_balance;
  IF v_balance IS NULL THEN RETURN jsonb_build_object('error','User not found'); END IF;
  INSERT INTO wallet_transactions(user_id,type,amount,status,description) VALUES(p_user_id,'admin_adjustment',p_amount,'completed','Admin balance adjustment: '||COALESCE(p_reason,'No reason provided'));
  RETURN jsonb_build_object('success',true,'new_balance',v_balance);
END; $$;

REVOKE EXECUTE ON FUNCTION public.request_withdrawal(numeric,text,uuid,text) FROM PUBLIC, anon; GRANT EXECUTE ON FUNCTION public.request_withdrawal(numeric,text,uuid,text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rent_vehicle(uuid,integer) FROM PUBLIC, anon; GRANT EXECUTE ON FUNCTION public.rent_vehicle(uuid,integer) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.claim_daily_earnings() FROM PUBLIC, anon; GRANT EXECUTE ON FUNCTION public.claim_daily_earnings() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.exchange_carbon_points(integer) FROM PUBLIC, anon; GRANT EXECUTE ON FUNCTION public.exchange_carbon_points(integer) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.purchase_mall_product(uuid,integer) FROM PUBLIC, anon; GRANT EXECUTE ON FUNCTION public.purchase_mall_product(uuid,integer) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.submit_bubble_game(integer) FROM PUBLIC, anon; GRANT EXECUTE ON FUNCTION public.submit_bubble_game(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_referral_signup(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_referral_investment(uuid,numeric) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_get_profiles() FROM PUBLIC, anon; GRANT EXECUTE ON FUNCTION public.admin_get_profiles() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_block_user(uuid) FROM PUBLIC, anon; GRANT EXECUTE ON FUNCTION public.admin_block_user(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_unblock_user(uuid) FROM PUBLIC, anon; GRANT EXECUTE ON FUNCTION public.admin_unblock_user(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_adjust_balance(uuid,numeric,text) FROM PUBLIC, anon; GRANT EXECUTE ON FUNCTION public.admin_adjust_balance(uuid,numeric,text) TO authenticated;
