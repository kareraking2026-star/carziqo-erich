/*
# Fix all database functions, seed car market, and create storage buckets

1. Purpose
- Updates all RPC functions to match the latest app code (30/60-day rental plans, carbon mall, proof of payment).
- Seeds the car market with all vehicle tiers so the Car Market page is not empty.
- Creates the avatars and payment-proofs storage buckets with proper RLS policies.

2. Updated Functions
- `rent_vehicle`: paid rentals now accept only 30 or 60 days (2% and 3% daily rate). Free trial unchanged.
- `admin_get_recharge_requests`: returns proof_path, transaction_hash, updated_at, member_nickname, member_phone.
- `admin_get_withdrawal_requests`: returns withdrawal address details and member info.
- `admin_approve_recharge`, `admin_reject_recharge`, `admin_approve_withdrawal`, `admin_reject_withdrawal`: fixed versions with idempotency guards and no double-charge.

3. Seeded Data
- 14 vehicles across standard, premium, and luxury categories with Pexels images.
- 1 free trial vehicle.

4. Storage
- `avatars` public bucket for user profile photos.
- `payment-proofs` private bucket for recharge proof screenshots.

5. Security
- Admin functions require is_admin() check.
- Storage policies restrict uploads to own folder; admins can read all proofs.
- No existing data is deleted.
*/

-- ============================================================
-- rent_vehicle: 30/60-day plans (latest version)
-- ============================================================
CREATE OR REPLACE FUNCTION public.rent_vehicle(p_vehicle_id uuid, p_rental_days integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_balance numeric;
  v_vehicle record;
  v_daily_rate numeric;
  v_daily_income numeric;
  v_total_income numeric;
  v_free_used boolean;
  v_existing_count integer;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT * INTO v_vehicle FROM vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Vehicle not found');
  END IF;

  IF v_vehicle.stock <= 0 THEN
    RETURN jsonb_build_object('error', 'Vehicle out of stock');
  END IF;

  SELECT wallet_balance, free_vehicle_used INTO v_balance, v_free_used
  FROM profiles WHERE user_id = v_user_id;

  IF v_balance IS NULL THEN
    RETURN jsonb_build_object('error', 'Profile not found');
  END IF;

  SELECT COUNT(*) INTO v_existing_count
  FROM rentals
  WHERE user_id = v_user_id AND vehicle_id = p_vehicle_id AND status = 'active';

  IF v_existing_count >= v_vehicle.rental_limit THEN
    RETURN jsonb_build_object('error', 'Rental limit reached for this vehicle');
  END IF;

  IF v_vehicle.is_free_vehicle THEN
    IF v_free_used THEN
      RETURN jsonb_build_object('error', 'Free trial already used');
    END IF;

    v_daily_income := v_vehicle.daily_return;
    v_total_income := v_vehicle.daily_return * v_vehicle.settlement_cycle;

    UPDATE profiles SET free_vehicle_used = true WHERE user_id = v_user_id;

    INSERT INTO rentals (user_id, vehicle_id, vehicle_name, rental_period, daily_income, total_income, status)
    VALUES (v_user_id, p_vehicle_id, v_vehicle.name, v_vehicle.settlement_cycle, v_daily_income, v_total_income, 'active');

    INSERT INTO wallet_transactions (user_id, type, amount, status, description)
    VALUES (v_user_id, 'free_trial', 0, 'completed', 'Free trial: ' || v_vehicle.name);

    UPDATE vehicles SET stock = stock - 1 WHERE id = p_vehicle_id;
  ELSE
    IF p_rental_days = 30 THEN
      v_daily_rate := 0.02;
    ELSIF p_rental_days = 60 THEN
      v_daily_rate := 0.03;
    ELSE
      RETURN jsonb_build_object('error', 'Rental period must be 30 or 60 days');
    END IF;

    IF v_vehicle.price > v_balance THEN
      RETURN jsonb_build_object('error', 'Insufficient wallet balance');
    END IF;

    v_daily_income := v_vehicle.price * v_daily_rate;
    v_total_income := v_daily_income * p_rental_days;

    UPDATE profiles SET wallet_balance = wallet_balance - v_vehicle.price WHERE user_id = v_user_id AND wallet_balance >= v_vehicle.price;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('error', 'Insufficient wallet balance');
    END IF;

    INSERT INTO rentals (user_id, vehicle_id, vehicle_name, rental_period, daily_income, total_income, status)
    VALUES (v_user_id, p_vehicle_id, v_vehicle.name, p_rental_days, v_daily_income, v_total_income, 'active');

    INSERT INTO wallet_transactions (user_id, type, amount, status, description)
    VALUES (v_user_id, 'rental', -v_vehicle.price, 'completed', 'Rented ' || v_vehicle.name);

    UPDATE vehicles SET stock = stock - 1 WHERE id = p_vehicle_id AND stock > 0;

    PERFORM process_referral_investment(v_user_id, v_vehicle.price);
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rent_vehicle(uuid, integer) TO authenticated;

-- ============================================================
-- Admin recharge/withdrawal functions (latest fixed versions)
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_approve_recharge(request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  req_user_id uuid;
  req_amount numeric;
  req_method text;
  req_status text;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT user_id, amount, method, status INTO req_user_id, req_amount, req_method, req_status
  FROM recharge_requests WHERE id = request_id;

  IF req_user_id IS NULL THEN
    RAISE EXCEPTION 'Recharge request not found';
  END IF;

  IF req_status = 'approved' THEN
    RAISE EXCEPTION 'Recharge already approved';
  END IF;

  IF req_status <> 'pending' THEN
    RAISE EXCEPTION 'Recharge request is not pending';
  END IF;

  UPDATE recharge_requests SET status = 'approved', updated_at = now() WHERE id = request_id;

  UPDATE profiles
  SET wallet_balance = COALESCE(wallet_balance, 0) + req_amount
  WHERE user_id = req_user_id;

  INSERT INTO wallet_transactions (user_id, type, amount, status, description)
  VALUES (req_user_id, 'recharge', req_amount, 'completed', 'Recharge approved via ' || req_method);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reject_recharge(request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  req_status text;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT status INTO req_status FROM recharge_requests WHERE id = request_id;
  IF req_status IS NULL THEN
    RAISE EXCEPTION 'Recharge request not found';
  END IF;

  IF req_status <> 'pending' THEN
    RAISE EXCEPTION 'Recharge request is not pending';
  END IF;

  UPDATE recharge_requests SET status = 'rejected', updated_at = now() WHERE id = request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_approve_withdrawal(request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  req_user_id uuid;
  req_amount numeric;
  req_status text;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT user_id, amount, status INTO req_user_id, req_amount, req_status
  FROM withdrawal_requests WHERE id = request_id;

  IF req_user_id IS NULL THEN
    RAISE EXCEPTION 'Withdrawal request not found';
  END IF;

  IF req_status = 'approved' THEN
    RAISE EXCEPTION 'Withdrawal already approved';
  END IF;

  IF req_status <> 'pending' THEN
    RAISE EXCEPTION 'Withdrawal request is not pending';
  END IF;

  UPDATE withdrawal_requests SET status = 'approved' WHERE id = request_id;

  UPDATE wallet_transactions
  SET status = 'completed', description = 'Withdrawal approved by admin'
  WHERE user_id = req_user_id
    AND type = 'withdrawal_hold'
    AND amount = -req_amount
    AND status = 'pending'
    AND created_at = (
      SELECT created_at FROM withdrawal_requests WHERE id = request_id
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reject_withdrawal(request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  req_user_id uuid;
  req_amount numeric;
  req_status text;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT user_id, amount, status INTO req_user_id, req_amount, req_status
  FROM withdrawal_requests WHERE id = request_id;

  IF req_user_id IS NULL THEN
    RAISE EXCEPTION 'Withdrawal request not found';
  END IF;

  IF req_status = 'rejected' THEN
    RAISE EXCEPTION 'Withdrawal already rejected';
  END IF;

  IF req_status <> 'pending' THEN
    RAISE EXCEPTION 'Withdrawal request is not pending';
  END IF;

  UPDATE withdrawal_requests SET status = 'rejected' WHERE id = request_id;

  UPDATE profiles
  SET wallet_balance = COALESCE(wallet_balance, 0) + req_amount
  WHERE user_id = req_user_id;

  UPDATE wallet_transactions
  SET status = 'completed', description = 'Withdrawal rejected - amount refunded'
  WHERE user_id = req_user_id
    AND type = 'withdrawal_hold'
    AND amount = -req_amount
    AND status = 'pending'
    AND created_at = (
      SELECT created_at FROM withdrawal_requests WHERE id = request_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_approve_recharge(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_recharge(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_approve_withdrawal(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_withdrawal(uuid) TO authenticated;

-- ============================================================
-- Admin get requests (latest with proof_path and member info)
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_get_recharge_requests();
CREATE FUNCTION public.admin_get_recharge_requests()
RETURNS TABLE(
  id uuid,
  user_id uuid,
  amount numeric,
  method text,
  status text,
  reference text,
  transaction_hash text,
  created_at timestamptz,
  updated_at timestamptz,
  member_nickname text,
  member_phone text,
  proof_path text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT r.id, r.user_id, r.amount, r.method, r.status, r.reference, r.transaction_hash,
         r.created_at, r.updated_at, p.nickname, p.phone, r.proof_path
  FROM recharge_requests r
  LEFT JOIN profiles p ON p.user_id = r.user_id
  ORDER BY r.created_at DESC
  LIMIT 200;
END;
$$;

DROP FUNCTION IF EXISTS public.admin_get_withdrawal_requests();
CREATE FUNCTION public.admin_get_withdrawal_requests()
RETURNS TABLE(
  id uuid,
  user_id uuid,
  amount numeric,
  method text,
  bank_card_id uuid,
  withdrawal_address_id uuid,
  status text,
  created_at timestamptz,
  addr_label text,
  addr_method text,
  addr_account_name text,
  addr_account_number text,
  addr_bank_name text,
  member_nickname text,
  member_phone text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT w.id, w.user_id, w.amount, w.method, w.bank_card_id, w.withdrawal_address_id,
         w.status, w.created_at,
         wa.label, wa.method, wa.account_name, wa.account_number, wa.bank_name,
         p.nickname, p.phone
  FROM withdrawal_requests w
  LEFT JOIN withdrawal_addresses wa ON wa.id = w.withdrawal_address_id
  LEFT JOIN profiles p ON p.user_id = w.user_id
  ORDER BY w.created_at DESC
  LIMIT 200;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_get_recharge_requests() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_get_withdrawal_requests() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_recharge_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_withdrawal_requests() TO authenticated;

-- ============================================================
-- Seed vehicle data
-- ============================================================
INSERT INTO vehicles (name, description, price, daily_return, image_url, stock, status, category, settlement_cycle, rental_limit, is_free_vehicle)
VALUES
  ('Carziqo Free Trial', 'Free 7-day trial vehicle — one per member. Experience passive income with no cost!', 0, 5, 'https://images.pexels.com/photos/20000977/pexels-photo-20000977.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', 999, 'available', 'standard', 7, 1, true),
  ('Carziqo Starter 500', 'Entry-level autonomous taxi perfect for first-time investors. Compact, efficient, and affordable.', 550, 4, 'https://images.pexels.com/photos/18379680/pexels-photo-18379680.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', 200, 'available', 'standard', 7, 5, false),
  ('Carziqo City Zip', 'Lightweight city pod designed for urban trips. Great daily returns at a low entry price.', 600, 5, 'https://images.pexels.com/photos/18370674/pexels-photo-18370674.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', 200, 'available', 'standard', 10, 5, false),
  ('Carziqo Eco Dash', 'Eco-friendly compact with fast charging and smart navigation. Reliable daily income.', 650, 5, 'https://images.pexels.com/photos/14436192/pexels-photo-14436192.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', 180, 'available', 'standard', 10, 5, false),
  ('Carziqo Urban Pod', 'Stylish urban commuter with a roomy interior and smooth ride quality.', 700, 6, 'https://images.pexels.com/photos/4014137/pexels-photo-4014137.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', 180, 'available', 'standard', 12, 5, false),
  ('Carziqo Green Runner', 'Green energy compact with extended range. Perfect for eco-conscious investors.', 750, 6, 'https://images.pexels.com/photos/7459481/pexels-photo-7459481.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', 160, 'available', 'standard', 12, 5, false),
  ('Carziqo Micro Cruiser', 'Reliable hatchback with great fuel efficiency and comfortable seating.', 800, 7, 'https://images.pexels.com/photos/27138933/pexels-photo-27138933.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', 160, 'available', 'standard', 14, 5, false),
  ('Carziqo Tech Drive', 'Advanced electric sedan with cutting-edge tech and premium comfort.', 15000, 85, 'https://images.pexels.com/photos/10029873/pexels-photo-10029873.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', 40, 'available', 'premium', 45, 2, false),
  ('Carziqo Business Class', 'Executive sedan with luxury interior and top-tier autonomous capabilities.', 20000, 120, 'https://images.pexels.com/photos/17233277/pexels-photo-17233277.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', 35, 'available', 'premium', 50, 2, false),
  ('Carziqo Pro Cruiser', 'High-performance SUV with premium features and excellent daily returns.', 35000, 220, 'https://images.pexels.com/photos/11396006/pexels-photo-11396006.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', 20, 'available', 'premium', 60, 2, false),
  ('Carziqo Elite SUV', 'Top-tier luxury SUV with advanced autonomous fleet management.', 45000, 300, 'https://images.pexels.com/photos/31118729/pexels-photo-31118729.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', 15, 'available', 'premium', 70, 1, false),
  ('Carziqo Executive', 'Premium executive sedan with unmatched comfort and prestige.', 70000, 480, 'https://images.pexels.com/photos/8662676/pexels-photo-8662676.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', 10, 'available', 'luxury', 80, 1, false),
  ('Carziqo Phantom Series', 'Ultra-luxury autonomous vehicle with bespoke interior and elite performance.', 85000, 600, 'https://images.pexels.com/photos/13058788/pexels-photo-13058788.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', 8, 'available', 'luxury', 90, 1, false),
  ('Carziqo Apex GT', 'The pinnacle of autonomous luxury. Limited stock, maximum returns.', 100000, 750, 'https://images.pexels.com/photos/29126220/pexels-photo-29126220.jpeg?auto=compress&cs=tinysrgb&h=650&w=940', 5, 'available', 'luxury', 100, 1, false)
ON CONFLICT DO NOTHING;

-- ============================================================
-- Storage buckets
-- ============================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "avatar_public_read" ON storage.objects;
CREATE POLICY "avatar_public_read"
ON storage.objects FOR SELECT
TO anon, authenticated
USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "avatar_upload_own" ON storage.objects;
CREATE POLICY "avatar_upload_own"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "avatar_update_own" ON storage.objects;
CREATE POLICY "avatar_update_own"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "avatar_delete_own" ON storage.objects;
CREATE POLICY "avatar_delete_own"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('payment-proofs', 'payment-proofs', false, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "payment_proof_upload_own" ON storage.objects;
CREATE POLICY "payment_proof_upload_own" ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'payment-proofs'
  AND (storage.foldername(name))[1] = (auth.uid())::text
);

DROP POLICY IF EXISTS "payment_proof_read_admin" ON storage.objects;
CREATE POLICY "payment_proof_read_admin" ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'payment-proofs'
  AND is_admin()
);
