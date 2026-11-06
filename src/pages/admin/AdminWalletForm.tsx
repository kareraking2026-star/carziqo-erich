import { useState, type FormEvent } from 'react';
import { supabase } from '@/lib/supabase';
import { useToast } from '@/context/ToastContext';
import { formatCurrency } from '@/lib/utils';
import Modal from '@/components/Modal';
import type { AdminMember } from '@/pages/admin/AdminMemberForm';
import { Loader as Loader2 } from 'lucide-react';

interface AdminWalletFormProps {
  member: AdminMember;
  onClose: () => void;
  onSaved: () => void;
}

const labelClass = 'text-xs font-medium text-[#9babc6] mb-1 block';

export default function AdminWalletForm({ member, onClose, onSaved }: AdminWalletFormProps) {
  const { showToast } = useToast();
  const [balance, setBalance] = useState(String(member.wallet_balance));
  const [reason, setReason] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  async function handleSave(e: FormEvent) {
    e.preventDefault();
    const amount = Number(balance);
    if (balance.trim() === '' || !Number.isFinite(amount) || amount < 0) {
      setError('Enter a wallet amount of 0 or more');
      return;
    }

    setSaving(true);
    setError('');
    const { error: rpcError } = await supabase.rpc('admin_set_wallet_balance', {
      p_user_id: member.user_id,
      p_new_balance: amount,
      p_reason: reason.trim(),
    });
    setSaving(false);

    if (rpcError) {
      setError(rpcError.message || 'Could not update the wallet');
      return;
    }
    showToast('Wallet updated', 'success');
    onSaved();
  }

  return (
    <Modal open onClose={onClose} title={`Wallet: ${member.nickname || 'Member'}`}>
      <form onSubmit={handleSave} className="space-y-4">
        <div className="rounded-xl bg-[#f0f3f8] p-3">
          <p className="text-[10px] text-[#9babc6] uppercase tracking-wide">Current balance</p>
          <p className="text-lg font-bold text-[#16a35a]">₱{formatCurrency(member.wallet_balance)}</p>
        </div>
        <div>
          <label htmlFor="wallet-balance" className={labelClass}>New wallet balance (₱)</label>
          <input
            id="wallet-balance"
            type="number"
            min="0"
            step="any"
            value={balance}
            onChange={(e) => setBalance(e.target.value)}
            className="input-field"
          />
        </div>
        <div>
          <label htmlFor="wallet-reason" className={labelClass}>Reason (recorded in history)</label>
          <input
            id="wallet-reason"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            className="input-field"
            placeholder="e.g. Correction after recharge review"
          />
        </div>

        {error && <p className="text-xs text-[#dc2626]">{error}</p>}

        <button type="submit" disabled={saving} className="btn-primary w-full flex items-center justify-center gap-2">
          {saving && <Loader2 size={16} className="animate-spin" />}
          Save wallet balance
        </button>
      </form>
    </Modal>
  );
}
