import { supabase } from '@/lib/supabase';

export type PaymentQrOverrides = Record<string, string>;

export async function fetchPaymentQrOverrides(): Promise<PaymentQrOverrides> {
  const { data, error } = await supabase.from('payment_qr_codes').select('method_key, image_url');
  if (error || !Array.isArray(data)) return {};
  return Object.fromEntries(data.map((row) => [row.method_key, row.image_url]));
}
