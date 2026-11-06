import { useState, type FormEvent } from 'react';
import { supabase } from '@/lib/supabase';
import { useToast } from '@/context/ToastContext';
import Modal from '@/components/Modal';
import { Loader as Loader2 } from 'lucide-react';

export interface AdminMember {
  id: string;
  user_id: string;
  nickname: string;
  phone: string;
  wallet_balance: number;
  carbon_points: number;
  vip_level: number;
  referral_code: string;
  created_at: string;
  is_blocked: boolean;
}

interface AdminMemberFormProps {
  member: AdminMember;
  onClose: () => void;
  onSaved: () => void;
}

const labelClass = 'text-xs font-medium text-[#9babc6] mb-1 block';

export default function AdminMemberForm({ member, onClose, onSaved }: AdminMemberFormProps) {
  const { showToast } = useToast();
  const [nickname, setNickname] = useState(member.nickname ?? '');
  const [phone, setPhone] = useState(member.phone ?? '');
  const [vipLevel, setVipLevel] = useState(String(member.vip_level));
  const [carbonPoints, setCarbonPoints] = useState(String(member.carbon_points));
  const [saving, setSaving] = useState(false);
  const [blockBusy, setBlockBusy] = useState(false);
  const [error, setError] = useState('');

  async function handleSave(e: FormEvent) {
    e.preventDefault();
    if (!nickname.trim()) {
      setError('Enter a nickname');
      return;
    }
    const vip = Number(vipLevel);
    const carbon = Number(carbonPoints);
    if (!Number.isInteger(vip) || vip < 0) {
      setError('VIP level must be a whole number of 0 or more');
      return;
    }
    if (!Number.isFinite(carbon) || carbon < 0) {
      setError('Carbon points must be 0 or more');
      return;
    }

    setSaving(true);
    setError('');
    const { error: rpcError } = await supabase.rpc('admin_update_member', {
      p_user_id: member.user_id,
      p_nickname: nickname.trim(),
      p_phone: phone.trim(),
      p_vip_level: vip,
      p_carbon_points: carbon,
    });
    setSaving(false);

    if (rpcError) {
      setError(rpcError.message || 'Could not save the member');
      return;
    }
    showToast('Member updated', 'success');
    onSaved();
  }

  async function toggleBlocked() {
    setBlockBusy(true);
    setError('');
    const fn = member.is_blocked ? 'admin_unblock_user' : 'admin_block_user';
    const { error: rpcError } = await supabase.rpc(fn, { p_user_id: member.user_id });
    setBlockBusy(false);

    if (rpcError) {
      setError('Could not change the account status');
      return;
    }
    showToast(member.is_blocked ? 'Account unblocked' : 'Account blocked', 'success');
    onSaved();
  }

  return (
    <Modal open onClose={onClose} title="Edit member">
      <form onSubmit={handleSave} className="space-y-4">
        <div>
          <label htmlFor="member-nickname" className={labelClass}>Nickname</label>
          <input id="member-nickname" value={nickname} onChange={(e) => setNickname(e.target.value)} className="input-field" />
        </div>
        <div>
          <label htmlFor="member-phone" className={labelClass}>Phone</label>
          <input id="member-phone" value={phone} onChange={(e) => setPhone(e.target.value)} className="input-field" />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label htmlFor="member-vip" className={labelClass}>VIP level</label>
            <input id="member-vip" type="number" min="0" step="1" value={vipLevel} onChange={(e) => setVipLevel(e.target.value)} className="input-field" />
          </div>
          <div>
            <label htmlFor="member-carbon" className={labelClass}>Carbon points</label>
            <input id="member-carbon" type="number" min="0" step="any" value={carbonPoints} onChange={(e) => setCarbonPoints(e.target.value)} className="input-field" />
          </div>
        </div>

        {error && <p className="text-xs text-[#dc2626]">{error}</p>}

        <button type="submit" disabled={saving} className="btn-primary w-full flex items-center justify-center gap-2">
          {saving && <Loader2 size={16} className="animate-spin" />}
          Save changes
        </button>
      </form>

      <div className="mt-4 pt-4 border-t border-[#dfe5f0]">
        <p className="text-xs font-medium text-[#323643] mb-2">Account status: {member.is_blocked ? 'Blocked' : 'Active'}</p>
        <button
          type="button"
          onClick={toggleBlocked}
          disabled={blockBusy}
          className="btn-outline w-full flex items-center justify-center gap-2"
        >
          {blockBusy && <Loader2 size={16} className="animate-spin" />}
          {member.is_blocked ? 'Unblock account' : 'Block account'}
        </button>
      </div>
    </Modal>
  );
}
