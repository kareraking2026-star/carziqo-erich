/*
# Restrict administrative and referral functions

1. Purpose
- Removes anonymous execution rights left behind by older migrations.

2. Security changes
- Only signed-in users can invoke admin approval/rejection functions.
- Only signed-in users can invoke referral processing functions.
- Existing function behavior and data remain unchanged.
*/

REVOKE EXECUTE ON FUNCTION public.admin_approve_recharge(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_reject_recharge(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_approve_withdrawal(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_reject_withdrawal(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.process_referral_signup(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.process_referral_investment(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_recharge(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_recharge(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_approve_withdrawal(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_withdrawal(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_referral_signup(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_referral_investment(uuid, numeric) TO authenticated;
