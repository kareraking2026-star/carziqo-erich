/*
# Repair admin auth record

1. Purpose
- Aligns the admin sign-in account with the auth record format used by working accounts so password sign-in succeeds.

2. Changes
- Sets the auth instance id and replaces NULL token columns with empty strings.
- Keeps the existing password, confirmation, and admin role unchanged.
*/

UPDATE auth.users
SET instance_id = '00000000-0000-0000-0000-000000000000',
    confirmation_token = COALESCE(confirmation_token, ''),
    recovery_token = COALESCE(recovery_token, ''),
    email_change_token_new = COALESCE(email_change_token_new, ''),
    email_change = COALESCE(email_change, ''),
    updated_at = now()
WHERE email = 'carziqo-admin@admin.carziqo.app';
