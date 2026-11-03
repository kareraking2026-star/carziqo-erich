import { TriangleAlert as AlertTriangle } from 'lucide-react';

export default function SetupNeeded() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-[#f0f3f8] px-4">
      <div className="card w-full max-w-md text-center">
        <div className="w-14 h-14 mx-auto rounded-2xl bg-[#fff8eb] flex items-center justify-center mb-4">
          <AlertTriangle size={28} className="text-[#ef9100]" />
        </div>
        <h1 className="text-lg font-semibold text-[#323643] mb-2">Database connection needs attention</h1>
        <p className="text-sm text-[#9babc6] leading-relaxed">
          The deployed site is missing a valid Supabase public connection key, so login and signup cannot reach the database.
          Add the current VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY values to the Netlify site, then publish a new deploy.
        </p>
      </div>
    </div>
  );
}
