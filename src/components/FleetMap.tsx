import { useEffect, useRef } from 'react';
import * as L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import {
  fetchDrivingRoute,
  positionOnRoute,
  randomPointNear,
  type CarRoute,
  type CarStatus,
  type LatLng,
} from '@/lib/fleet';
import { bodyColorFor, createCarIcon, type CarVisual } from '@/components/fleetCarIcon';

export interface FleetCar {
  id: string;
  name: string;
  dailyIncome: number;
}

export interface FleetCarState {
  status: CarStatus;
  speedKmh: number;
}

type TripLeg = 'pickup' | 'dropoff';

interface CarSim {
  visual: CarVisual;
  position: LatLng;
  heading: number;
  route: CarRoute | null;
  leg: TripLeg;
  distance: number;
  speed: number;
  cruiseSpeed: number;
  dwellUntil: number;
  retryAt: number;
  status: CarStatus;
  controller: AbortController | null;
  marker: L.Marker;
}

const BASE_CENTER: LatLng = [34.0522, -118.2437];
const CRUISE_MIN_MPS = 4;
const CRUISE_MAX_MPS = 6.5;
const ACCELERATION_MPS2 = 0.35;
const BRAKING_MPS2 = 0.7;
const CRAWL_MPS = 1.2;
const SLOW_ZONE_M = 40;
const PICKUP_MIN_M = 300;
const PICKUP_MAX_M = 1500;
const TRIP_MIN_M = 400;
const TRIP_MAX_M = 1800;
const BOARDING_MIN_MS = 5_000;
const BOARDING_MAX_MS = 9_000;
const ALIGHTING_MIN_MS = 4_000;
const ALIGHTING_MAX_MS = 7_000;
const PARKED_MIN_MS = 15_000;
const PARKED_MAX_MS = 40_000;
const RETRY_MS = 15_000;

function randomBetween(min: number, max: number): number {
  return min + Math.random() * (max - min);
}

function setStatus(sim: CarSim, status: CarStatus) {
  if (sim.status === status) return;
  sim.status = status;
  sim.marker.setIcon(createCarIcon(sim.visual, status));
}

function applyHeading(sim: CarSim) {
  const el = sim.marker.getElement()?.querySelector<HTMLElement>('.fleet-car-body');
  if (el) el.style.transform = `rotate(${sim.heading}deg)`;
}

function pauseAt(sim: CarSim, status: CarStatus, minMs: number, maxMs: number, now: number) {
  sim.route = null;
  sim.speed = 0;
  sim.controller = null;
  sim.dwellUntil = now + randomBetween(minMs, maxMs);
  setStatus(sim, status);
}

function startTrip(sim: CarSim, leg: TripLeg) {
  sim.controller?.abort();
  const controller = new AbortController();
  sim.controller = controller;
  sim.leg = leg;
  setStatus(sim, 'routing');

  const destination =
    leg === 'pickup'
      ? randomPointNear(sim.position, PICKUP_MIN_M, PICKUP_MAX_M)
      : randomPointNear(sim.position, TRIP_MIN_M, TRIP_MAX_M);

  fetchDrivingRoute(sim.position, destination, controller.signal)
    .then((route) => {
      if (controller.signal.aborted) return;
      sim.route = route;
      sim.position = route.points[0];
      sim.distance = 0;
      sim.speed = 0;
      sim.cruiseSpeed = randomBetween(CRUISE_MIN_MPS, CRUISE_MAX_MPS);
      setStatus(sim, leg === 'pickup' ? 'to-pickup' : 'carrying');
    })
    .catch(() => {
      if (controller.signal.aborted) return;
      sim.route = null;
      sim.retryAt = performance.now() + RETRY_MS;
      setStatus(sim, 'error');
    });
}

function moveCar(sim: CarSim, dt: number, now: number) {
  const route = sim.route;
  if (!route) return;
  const remaining = route.total - sim.distance;
  const target = remaining < SLOW_ZONE_M ? CRAWL_MPS : sim.cruiseSpeed;
  const rate = target > sim.speed ? ACCELERATION_MPS2 : BRAKING_MPS2;
  const delta = target - sim.speed;
  sim.speed = Math.max(0, sim.speed + Math.max(-rate * dt, Math.min(rate * dt, delta)));
  sim.distance = Math.min(route.total, sim.distance + sim.speed * dt);

  const { position, heading } = positionOnRoute(route, sim.distance);
  sim.position = position;
  sim.heading = heading;

  if (sim.distance < route.total) return;
  if (sim.status === 'to-pickup') {
    pauseAt(sim, 'boarding', BOARDING_MIN_MS, BOARDING_MAX_MS, now);
  } else {
    pauseAt(sim, 'alighting', ALIGHTING_MIN_MS, ALIGHTING_MAX_MS, now);
  }
}

function stepCar(sim: CarSim, dt: number, now: number) {
  switch (sim.status) {
    case 'parked':
      if (now >= sim.dwellUntil) startTrip(sim, 'pickup');
      break;
    case 'boarding':
      if (now >= sim.dwellUntil) startTrip(sim, 'dropoff');
      break;
    case 'alighting':
      if (now >= sim.dwellUntil) pauseAt(sim, 'parked', PARKED_MIN_MS, PARKED_MAX_MS, now);
      break;
    case 'error':
      if (now >= sim.retryAt) startTrip(sim, sim.leg);
      break;
    case 'to-pickup':
    case 'carrying':
      moveCar(sim, dt, now);
      break;
  }
}

interface FleetMapProps {
  cars: FleetCar[];
  onStatusChange: (states: Record<string, FleetCarState>) => void;
}

export default function FleetMap({ cars, onStatusChange }: FleetMapProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const simsRef = useRef(new Map<string, CarSim>());
  const onStatusRef = useRef(onStatusChange);
  onStatusRef.current = onStatusChange;

  useEffect(() => {
    if (!containerRef.current) return;
    const map = L.map(containerRef.current, { zoomControl: false }).setView(BASE_CENTER, 14);
    L.control.zoom({ position: 'bottomright' }).addTo(map);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(map);
    mapRef.current = map;

    const sims = simsRef.current;
    return () => {
      sims.forEach((sim) => sim.controller?.abort());
      sims.clear();
      map.remove();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    const sims = simsRef.current;
    const ids = new Set(cars.map((car) => car.id));

    sims.forEach((sim, id) => {
      if (ids.has(id)) return;
      sim.controller?.abort();
      sim.marker.remove();
      sims.delete(id);
    });

    cars.forEach((car) => {
      if (sims.has(car.id)) return;
      const visual: CarVisual = {
        name: car.name,
        dailyIncome: car.dailyIncome,
        color: bodyColorFor(car.id),
      };
      const position = randomPointNear(BASE_CENTER, 300, 3000);
      const marker = L.marker(position, { icon: createCarIcon(visual, 'parked'), keyboard: false }).addTo(map);
      sims.set(car.id, {
        visual,
        position,
        heading: 0,
        route: null,
        leg: 'pickup',
        distance: 0,
        speed: 0,
        cruiseSpeed: CRUISE_MIN_MPS,
        dwellUntil: performance.now() + Math.random() * 5000,
        retryAt: 0,
        status: 'parked',
        controller: null,
        marker,
      });
    });

    if (sims.size > 0) {
      const bounds = L.latLngBounds(Array.from(sims.values(), (sim) => sim.position));
      map.fitBounds(bounds.pad(0.3), { maxZoom: 15 });
    }
  }, [cars]);

  useEffect(() => {
    let frameId = 0;
    let last = performance.now();
    let lastReport = 0;

    const tick = (now: number) => {
      const dt = Math.min((now - last) / 1000, 0.1);
      last = now;
      const report: Record<string, FleetCarState> = {};

      simsRef.current.forEach((sim, id) => {
        stepCar(sim, dt, now);
        sim.marker.setLatLng(sim.position);
        applyHeading(sim);
        report[id] = { status: sim.status, speedKmh: Math.round(sim.speed * 3.6) };
      });

      if (now - lastReport >= 1000) {
        lastReport = now;
        onStatusRef.current(report);
      }
      frameId = requestAnimationFrame(tick);
    };

    frameId = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frameId);
  }, []);

  return <div ref={containerRef} className="w-full h-full" />;
}
