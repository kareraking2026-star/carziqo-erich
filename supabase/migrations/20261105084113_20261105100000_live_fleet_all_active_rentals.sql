/*
# Live fleet: all active rentals

1. Purpose
- Lets any signed-in member see every active rented car on the Live Fleet page.
- Rentals are otherwise visible only to their owner, so this runs as a definer function.

2. Privacy
- Owners are returned only as an anonymous label derived from their id; no names, emails or balances.

3. Security
- Read-only; execute is granted to signed-in users only.
*/

CREATE OR REPLACE FUNCTION public.get_live_fleet()
RETURNS TABLE (
  rental_id uuid,
  vehicle_name text,
  vehicle_image_url text,
  daily_income numeric,
  total_income numeric,
  rental_period integer,
  created_at timestamptz,
  owner_label text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    r.id,
    r.vehicle_name,
    v.image_url,
    r.daily_income,
    r.total_income,
    r.rental_period,
    r.created_at,
    'Member ' || upper(left(md5(r.user_id::text), 4))
  FROM public.rentals r
  LEFT JOIN public.vehicles v ON v.id = r.vehicle_id
  WHERE r.status = 'active'
  ORDER BY r.created_at ASC
  LIMIT 500;
$$;

REVOKE EXECUTE ON FUNCTION public.get_live_fleet() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_live_fleet() TO authenticated;
