import { useCallback, useEffect, useState, type ChangeEvent } from 'react';
import { supabase } from '@/lib/supabase';
import { useToast } from '@/context/ToastContext';
import { uploadAdminImage } from '@/lib/adminMedia';
import { fetchPaymentQrOverrides, type PaymentQrOverrides } from '@/lib/paymentQr';
import { paymentMethods } from '@/lib/paymentMethods';
import LoadingSpinner from '@/components/LoadingSpinner';
import { Loader as Loader2, QrCode, Upload } from 'lucide-react';

export default function AdminPaymentQr() {
  const { showToast } = useToast();
  const [overrides, setOverrides] = useState<PaymentQrOverrides>({});
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setOverrides(await fetchPaymentQrOverrides());
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function handleUpload(methodId: string, e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;

    setBusyId(methodId);
    try {
      const url = await uploadAdminImage(file, 'payment-qr');
      const { error } = await supabase.rpc('admin_set_payment_qr', {
        p_method_key: methodId,
        p_image_url: url,
      });
      if (error) throw error;
      showToast('QR code updated', 'success');
      await load();
    } catch (err) {
      showToast(err instanceof Error ? err.message : 'Could not upload the QR code', 'error');
    }
    setBusyId(null);
  }

  if (loading) return <LoadingSpinner label="Loading payment QR codes..." />;

  return (
    <div className="space-y-3">
      <p className="text-[11px] text-[#9babc6]">
        Upload the QR code for each payment method. Users see it on the recharge page right away.
      </p>
      <div className="space-y-2">
        {paymentMethods.map((m) => {
          const src = overrides[m.id] ?? m.qrImage;
          const isCustom = Boolean(overrides[m.id]);
          return (
            <div key={m.id} className="card flex items-center gap-3">
              <div className="w-16 h-16 rounded-lg overflow-hidden bg-[#f0f3f8] flex-shrink-0 flex items-center justify-center">
                <img src={src} alt={`${m.label} QR code`} className="w-full h-full object-cover" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-[#323643] truncate">{m.label}</p>
                <p className="text-[10px] text-[#9babc6] truncate">{m.network}</p>
                <p className="text-[10px] text-[#9babc6] flex items-center gap-1">
                  <QrCode size={10} /> {isCustom ? 'Custom QR uploaded' : 'Using default QR'}
                </p>
              </div>
              <label className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg border border-[#dfe5f0] text-[11px] text-[#323643] hover:border-[#16a35a] cursor-pointer transition-colors flex-shrink-0">
                {busyId === m.id ? <Loader2 size={12} className="animate-spin" /> : <Upload size={12} />}
                {busyId === m.id ? 'Uploading' : 'Upload'}
                <input
                  type="file"
                  accept="image/jpeg,image/png,image/webp"
                  className="hidden"
                  disabled={busyId !== null}
                  onChange={(e) => handleUpload(m.id, e)}
                />
              </label>
            </div>
          );
        })}
      </div>
    </div>
  );
}
