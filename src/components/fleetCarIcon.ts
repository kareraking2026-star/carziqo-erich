import * as L from 'leaflet';
import { STATUS_LABELS, type CarStatus } from '@/lib/fleet';
import { formatCurrency } from '@/lib/utils';

export interface CarVisual {
  name: string;
  dailyIncome: number;
  color: string;
}

const BODY_COLORS = ['#4fc3f7', '#2979ff', '#f8fafc', '#16a35a', '#ef9100', '#ef4444'];

const STATUS_DOT: Record<CarStatus, string> = {
  routing: '#9babc6',
  'to-pickup': '#2979ff',
  boarding: '#ef9100',
  carrying: '#16a35a',
  alighting: '#ef9100',
  parked: '#9babc6',
  error: '#ef4444',
};

export function bodyColorFor(id: string): string {
  let hash = 0;
  for (let i = 0; i < id.length; i++) hash = (hash * 31 + id.charCodeAt(i)) >>> 0;
  return BODY_COLORS[hash % BODY_COLORS.length];
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function carSvg(color: string): string {
  return `<svg viewBox="0 0 60 110" width="16" height="30" xmlns="http://www.w3.org/2000/svg">
    <rect x="0" y="22" width="6" height="12" rx="2" fill="#1e293b"/>
    <rect x="54" y="22" width="6" height="12" rx="2" fill="#1e293b"/>
    <rect x="0" y="74" width="6" height="12" rx="2" fill="#1e293b"/>
    <rect x="54" y="74" width="6" height="12" rx="2" fill="#1e293b"/>
    <rect x="4" y="6" width="52" height="98" rx="20" fill="${color}" stroke="#0f172a" stroke-opacity="0.3" stroke-width="2"/>
    <path d="M14 24 Q30 16 46 24 L43 42 H17 Z" fill="#0b3b5c"/>
    <rect x="17" y="42" width="26" height="30" rx="4" fill="#ffffff" fill-opacity="0.25"/>
    <path d="M17 72 H43 L46 88 Q30 94 14 88 Z" fill="#0b3b5c"/>
    <ellipse cx="14" cy="10" rx="5" ry="3" fill="#fde68a"/>
    <ellipse cx="46" cy="10" rx="5" ry="3" fill="#fde68a"/>
    <ellipse cx="14" cy="102" rx="5" ry="3" fill="#f87171"/>
    <ellipse cx="46" cy="102" rx="5" ry="3" fill="#f87171"/>
  </svg>`;
}

export function createCarIcon(visual: CarVisual, status: CarStatus): L.DivIcon {
  const html = `<div style="position:relative;width:0;height:0">
    <div class="fleet-car-body" style="position:absolute;left:-8px;top:-15px;width:16px;height:30px;transform-origin:50% 50%;filter:drop-shadow(0 2px 3px rgba(15,23,42,0.35))">${carSvg(visual.color)}</div>
    <div style="position:absolute;left:0;top:18px;transform:translateX(-50%);white-space:nowrap;background:#ffffff;border:1px solid #dfe5f0;border-radius:8px;padding:2px 6px;box-shadow:0 1px 4px rgba(15,23,42,0.15);text-align:center;font-family:inherit">
      <div style="font-size:9px;font-weight:600;color:#323643;max-width:110px;overflow:hidden;text-overflow:ellipsis">${escapeHtml(visual.name)}</div>
      <div style="font-size:9px;font-weight:600;color:#16a35a">₱${formatCurrency(visual.dailyIncome)}/day</div>
      <div style="display:flex;align-items:center;justify-content:center;gap:3px;font-size:8px;color:#64748b">
        <span style="width:6px;height:6px;border-radius:9999px;background:${STATUS_DOT[status]}"></span>${STATUS_LABELS[status]}
      </div>
    </div>
  </div>`;
  return L.divIcon({ className: 'fleet-marker', iconSize: [1, 1], iconAnchor: [0, 0], html });
}
