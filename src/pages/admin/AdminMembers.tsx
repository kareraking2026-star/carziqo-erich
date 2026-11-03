import { useEffect, useMemo, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { formatCurrency, formatDate } from '@/lib/utils';
import LoadingSpinner from '@/components/LoadingSpinner';
import { EmptyState } from '@/components/UI';
import { Search, Users } from 'lucide-react';

interface MemberRow {
  id: string;
  nickname: string;
  phone: string;
  wallet_balance: number;
  carbon_points: number;
  vip_level: number;
  referral_code: string;
  created_at: string;
}

export default function AdminMembers() {
  const [members, setMembers] = useState<MemberRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [query, setQuery] = useState('');

  useEffect(() => {
    (async () => {
      const { data, error: rpcError } = await supabase.rpc('admin_get_profiles');
      if (rpcError || !Array.isArray(data)) {
        setError(true);
      } else {
        setMembers(data as MemberRow[]);
      }
      setLoading(false);
    })();
  }, []);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return members;
    return members.filter((m) =>
      (m.nickname || '').toLowerCase().includes(q) ||
      (m.phone || '').toLowerCase().includes(q) ||
      (m.referral_code || '').toLowerCase().includes(q),
    );
  }, [members, query]);

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
                <p className="text-sm font-medium text-[#323643] truncate">{m.nickname || 'Unknown'}</p>
                <p className="text-[10px] text-[#9babc6] truncate">{m.phone || 'No phone'} • Code {m.referral_code || '-'}</p>
                <p className="text-[10px] text-[#9babc6]">Joined {formatDate(m.created_at)}</p>
              </div>
              <div className="text-right flex-shrink-0">
                <p className="text-sm font-semibold text-[#16a35a]">₱{formatCurrency(m.wallet_balance)}</p>
                <p className="text-[10px] text-[#9babc6]">VIP {m.vip_level}</p>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
