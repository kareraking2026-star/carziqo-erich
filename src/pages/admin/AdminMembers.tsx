import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { formatCurrency, formatDate } from '@/lib/utils';
import LoadingSpinner from '@/components/LoadingSpinner';
import { EmptyState } from '@/components/UI';
import AdminMemberForm, { type AdminMember } from '@/pages/admin/AdminMemberForm';
import AdminWalletForm from '@/pages/admin/AdminWalletForm';
import { Search, Users, Pencil, Wallet } from 'lucide-react';

type Mode = 'edit' | 'wallet';

export default function AdminMembers() {
  const [members, setMembers] = useState<AdminMember[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [query, setQuery] = useState('');
  const [active, setActive] = useState<{ member: AdminMember; mode: Mode } | null>(null);

  const load = useCallback(async () => {
    const { data, error: rpcError } = await supabase.rpc('admin_get_profiles');
    if (rpcError || !Array.isArray(data)) {
      setError(true);
    } else {
      setError(false);
      setMembers(data as AdminMember[]);
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return members;
    return members.filter((m) =>
      (m.nickname || '').toLowerCase().includes(q) ||
      (m.phone || '').toLowerCase().includes(q) ||
      (m.referral_code || '').toLowerCase().includes(q),
    );
  }, [members, query]);

  function handleSaved() {
    setActive(null);
    load();
  }

  if (loading) return <LoadingSpinner label="Loading members..." />;
  if (error) return <EmptyState icon={Users} title="Could not load members" subtitle="Check your admin session and try again." />;

  return (
    <div className="space-y-3">
      <div className="relative">
        <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-[#9babc6]" />
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search name, phone, or referral code"
          className="input-field pl-9"
        />
      </div>

      <p className="text-[11px] text-[#9babc6]">{filtered.length} of {members.length} members</p>

      {filtered.length === 0 ? (
        <EmptyState icon={Users} title="No members found" />
      ) : (
        <div className="space-y-2">
          {filtered.map((m) => (
            <div key={m.id} className="card flex items-center gap-3">
              <div className="w-10 h-10 rounded-full bg-[#16a35a] flex items-center justify-center text-white font-bold text-sm flex-shrink-0">
                {m.nickname?.charAt(0).toUpperCase() || '?'}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-[#323643] truncate">
                  {m.nickname || 'Unknown'}
                  {m.is_blocked && <span className="ml-2 text-[10px] text-[#dc2626]">Blocked</span>}
                </p>
                <p className="text-[10px] text-[#9babc6] truncate">{m.phone || 'No phone'} • Code {m.referral_code || '-'}</p>
                <p className="text-[10px] text-[#9babc6]">Joined {formatDate(m.created_at)}</p>
                <p className="text-[10px] text-[#9babc6]">VIP {m.vip_level} • ₱{formatCurrency(m.wallet_balance)}</p>
              </div>
              <div className="flex flex-col gap-1.5 flex-shrink-0">
                <button
                  onClick={() => setActive({ member: m, mode: 'edit' })}
                  className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg border border-[#dfe5f0] text-[11px] text-[#323643] hover:border-[#16a35a] transition-colors"
                >
                  <Pencil size={12} /> Edit
                </button>
                <button
                  onClick={() => setActive({ member: m, mode: 'wallet' })}
                  className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg border border-[#dfe5f0] text-[11px] text-[#323643] hover:border-[#16a35a] transition-colors"
                >
                  <Wallet size={12} /> Wallet
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {active?.mode === 'edit' && (
        <AdminMemberForm member={active.member} onClose={() => setActive(null)} onSaved={handleSaved} />
      )}
      {active?.mode === 'wallet' && (
        <AdminWalletForm member={active.member} onClose={() => setActive(null)} onSaved={handleSaved} />
      )}
    </div>
  );
}
