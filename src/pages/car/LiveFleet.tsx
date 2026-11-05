import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/context/AuthContext';
import { formatCurrency } from '@/lib/utils';
import { rentalProgress } from '@/lib/fleet';
import AppLayout from '@/components/AppLayout';
import PageHeader from '@/components/PageHeader';
import LoadingSpinner from '@/components/LoadingSpinner';
import FleetMap, { type CarStatus, type FleetCarState } from '@/components/FleetMap';
import { EmptyState } from '@/components/UI';
import { Car, ChevronDown, Gauge, CircleAlert as AlertCircle } from 'lucide-react';

interface ActiveRental {
  id: string;
  vehicle_name: string;
  daily_income: number;
  total_income: number;
  rental_period: number;
  created_at: string;
}

const STATUS_LABELS: Record<CarStatus, string> = {
  routing: 'Finding route',
  driving: 'On the road',
  parked: 'Parked',
  error: 'Route unavailable, retrying',
};

const STATUS_COLORS: Record<CarStatus, string> = {
  routing: 'text-[#ef9100]',
  driving: 'text-[#16a35a]',
  parked: 'text-[#ef9100]',
  error: 'text-[#ef4444]',
};

export default function LiveFleet() {
  const navigate = useNavigate();
  const { profile } = useAuth();
  const [rentals, setRentals] = useState<ActiveRental[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadFailed, setLoadFailed] = useState(false);
  const [carStates, setCarStates] = useState<Record<string, FleetCarState>>({});
  const [expandedId, setExpandedId] = useState<string | null>(null);

  useEffect(() => {
    if (profile?.user_id) loadRentals(profile.user_id);
  }, [profile?.user_id]);

  async function loadRentals(userId: string) {
    const { data, error } = await supabase
      .from('rentals')
      .select('id, vehicle_name, daily_income, total_income, rental_period, created_at')
      .eq('user_id', userId)
      .eq('status', 'active')
      .order('created_at', { ascending: true });
    if (error) {
      setLoadFailed(true);
    } else {
      setRentals((data ?? []) as ActiveRental[]);
    }
    setLoading(false);
  }

  const cars = useMemo(
    () => rentals.map((r) => ({ id: r.id, name: r.vehicle_name })),
    [rentals],
  );

  const handleStatusChange = useCallback((states: Record<string, FleetCarState>) => {
    setCarStates(states);
  }, []);

  return (
    <AppLayout>
      <PageHeader title="Live Fleet" backPath="/my-cars" />
      <div className="px-4 py-3">
        {loading ? (
          <LoadingSpinner label="Loading your fleet..." />
        ) : loadFailed ? (
          <div className="card flex items-start gap-3">
            <AlertCircle size={20} className="text-[#ef4444] flex-shrink-0 mt-0.5" />
            <div>
              <p className="text-sm font-medium text-[#323643]">Could not load your fleet</p>
              <p className="text-xs text-[#9babc6] mt-0.5">Please go back and try again in a moment.</p>
            </div>
          </div>
        ) : rentals.length === 0 ? (
          <>
            <EmptyState icon={Car} title="No active vehicles" subtitle="Rent a vehicle to see it move on the live map" />
            <button onClick={() => navigate('/car-market')} className="btn-primary w-full mt-4">
              Go to Car Market
            </button>
          </>
        ) : (
          <>
            <div className="relative h-[360px] rounded-2xl overflow-hidden border border-[#dfe5f0] mb-2">
              <FleetMap cars={cars} onStatusChange={handleStatusChange} />
            </div>
            <p className="text-[10px] text-[#9babc6] mb-4">
              Vehicles follow real roads at city speeds and pause at each stop. Positions are simulated for your active rentals.
            </p>

            <div className="space-y-3">
              {rentals.map((r) => {
                const state = carStates[r.id];
                const status = state?.status ?? 'parked';
                const isOpen = expandedId === r.id;
                const { elapsedDays, daysRemaining } = rentalProgress(r.created_at, r.rental_period);
                return (
                  <div key={r.id} className="card">
                    <button
                      onClick={() => setExpandedId(isOpen ? null : r.id)}
                      className="w-full flex items-center justify-between gap-3 text-left"
                      aria-expanded={isOpen}
                    >
                      <div className="min-w-0">
                        <h3 className="text-sm font-semibold text-[#323643] truncate">{r.vehicle_name}</h3>
                        <p className={`text-xs font-medium ${STATUS_COLORS[status]}`}>{STATUS_LABELS[status]}</p>
                      </div>
                      <div className="flex items-center gap-2 flex-shrink-0">
                        <div className="text-right">
                          <p className="flex items-center justify-end gap-1 text-sm font-semibold text-[#323643]">
                            <Gauge size={14} className="text-[#2979ff]" />
                            {state?.speedKmh ?? 0} km/h
                          </p>
                          <p className="text-[10px] text-[#9babc6]">Earns ₱{formatCurrency(r.daily_income)}/day</p>
                        </div>
                        <ChevronDown
                          size={16}
                          className={`text-[#9babc6] transition-transform duration-200 ${isOpen ? 'rotate-180' : ''}`}
                        />
                      </div>
                    </button>

                    {isOpen && (
                      <dl className="grid grid-cols-2 gap-3 mt-4 pt-4 border-t border-[#dfe5f0]">
                        <div>
                          <dt className="text-[10px] text-[#9babc6]">Daily earnings</dt>
                          <dd className="text-sm font-semibold text-[#16a35a]">₱{formatCurrency(r.daily_income)}</dd>
                        </div>
                        <div>
                          <dt className="text-[10px] text-[#9babc6]">Total income</dt>
                          <dd className="text-sm font-semibold text-[#323643]">₱{formatCurrency(r.total_income)}</dd>
                        </div>
                        <div>
                          <dt className="text-[10px] text-[#9babc6]">Rental period</dt>
                          <dd className="text-sm font-semibold text-[#323643]">{r.rental_period} days</dd>
                        </div>
                        <div>
                          <dt className="text-[10px] text-[#9babc6]">Days remaining</dt>
                          <dd className="text-sm font-semibold text-[#323643]">
                            {daysRemaining} of {r.rental_period}
                          </dd>
                        </div>
                        <div className="col-span-2">
                          <div className="flex justify-between text-[10px] text-[#9babc6] mb-1">
                            <span>Progress</span>
                            <span>{elapsedDays} days elapsed</span>
                          </div>
                          <div className="h-1.5 rounded-full bg-[#f0f3f8] overflow-hidden">
                            <div
                              className="h-full rounded-full bg-[#16a35a] transition-all duration-500"
                              style={{ width: `${(elapsedDays / r.rental_period) * 100}%` }}
                            />
                          </div>
                        </div>
                      </dl>
                    )}
                  </div>
                );
              })}
            </div>
          </>
        )}
      </div>
    </AppLayout>
  );
}
