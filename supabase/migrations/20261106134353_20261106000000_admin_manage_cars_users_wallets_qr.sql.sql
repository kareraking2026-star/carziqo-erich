insert into storage.buckets (id, name, public) values ('admin-media', 'admin-media', true) on conflict (id) do nothing;

create policy "admin_media_public_read" on storage.objects for select to anon, authenticated
  using (bucket_id = 'admin-media');
create policy "admin_media_admin_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'admin-media' and is_admin());
create policy "admin_media_admin_update" on storage.objects for update to authenticated
  using (bucket_id = 'admin-media' and is_admin()) with check (bucket_id = 'admin-media' and is_admin());
create policy "admin_media_admin_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'admin-media' and is_admin());

grant insert, update on public.vehicles to authenticated;
create policy "admin_insert_vehicles" on public.vehicles for insert to authenticated
  with check (is_admin());
create policy "admin_update_vehicles" on public.vehicles for update to authenticated
  using (is_admin()) with check (is_admin());

create table if not exists public.payment_qr_codes (
  method_key text primary key,
  image_url text not null,
  updated_at timestamptz not null default now()
);
alter table public.payment_qr_codes enable row level security;
grant select on public.payment_qr_codes to anon, authenticated;
create policy "payment_qr_public_read" on public.payment_qr_codes for select to anon, authenticated using (true);

create or replace function public.admin_update_member(
  p_user_id uuid, p_nickname text, p_phone text, p_vip_level integer, p_carbon_points numeric
) returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not is_admin() then raise exception 'Admin access required'; end if;
  if p_nickname is null or btrim(p_nickname) = '' then raise exception 'Nickname is required'; end if;
  if p_vip_level is null or p_vip_level < 0 then raise exception 'VIP level must be 0 or more'; end if;
  if p_carbon_points is null or p_carbon_points < 0 then raise exception 'Carbon points must be 0 or more'; end if;
  update profiles
     set nickname = btrim(p_nickname),
         phone = btrim(coalesce(p_phone, '')),
         vip_level = p_vip_level,
         carbon_points = p_carbon_points
   where user_id = p_user_id;
  if not found then raise exception 'User not found'; end if;
end;
$$;

create or replace function public.admin_set_wallet_balance(p_user_id uuid, p_new_balance numeric, p_reason text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_old numeric; v_delta numeric;
begin
  if not is_admin() then raise exception 'Admin access required'; end if;
  if p_new_balance is null or p_new_balance < 0 then raise exception 'Balance must be 0 or more'; end if;
  select coalesce(wallet_balance, 0) into v_old from profiles where user_id = p_user_id for update;
  if not found then raise exception 'User not found'; end if;
  v_delta := p_new_balance - v_old;
  if v_delta = 0 then return jsonb_build_object('success', true, 'new_balance', v_old); end if;
  update profiles set wallet_balance = p_new_balance where user_id = p_user_id;
  insert into wallet_transactions (user_id, type, amount, status, description)
  values (p_user_id, 'admin_adjustment', v_delta, 'completed',
          'Admin wallet edit: ' || coalesce(nullif(btrim(p_reason), ''), 'No reason provided'));
  return jsonb_build_object('success', true, 'new_balance', p_new_balance);
end;
$$;

create or replace function public.admin_set_payment_qr(p_method_key text, p_image_url text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not is_admin() then raise exception 'Admin access required'; end if;
  if p_method_key is null or btrim(p_method_key) = '' then raise exception 'Payment method is required'; end if;
  if p_image_url is null or p_image_url !~* '^https?://' then raise exception 'Invalid image link'; end if;
  insert into payment_qr_codes (method_key, image_url, updated_at)
  values (p_method_key, p_image_url, now())
  on conflict (method_key) do update set image_url = excluded.image_url, updated_at = now();
end;
$$;

revoke execute on function public.admin_update_member(uuid, text, text, integer, numeric) from public, anon;
revoke execute on function public.admin_set_wallet_balance(uuid, numeric, text) from public, anon;
revoke execute on function public.admin_set_payment_qr(text, text) from public, anon;
grant execute on function public.admin_update_member(uuid, text, text, integer, numeric) to authenticated;
grant execute on function public.admin_set_wallet_balance(uuid, numeric, text) to authenticated;
grant execute on function public.admin_set_payment_qr(text, text) to authenticated;
