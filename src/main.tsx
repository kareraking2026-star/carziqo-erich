import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import SetupNeeded from './components/SetupNeeded';
import './index.css';

const root = createRoot(document.getElementById('root')!);

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://tmfkfshciqozvxzuhnsp.supabase.co';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRtZmtmc2hjaXFvenZ4enVobnNwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM3MDQ4MTQsImV4cCI6MjEwOTI4MDgxNH0.QlVRBq6u8LAfRikXdLykSYXVTQpgEaNODSW-ZdBzq9U';
const isConfigured = Boolean(supabaseUrl && supabaseAnonKey);

if (isConfigured) {
  import('./AppRoot').then(({ default: AppRoot }) => {
    root.render(
      <StrictMode>
        <AppRoot />
      </StrictMode>,
    );
  });
} else {
  root.render(
    <StrictMode>
      <SetupNeeded />
    </StrictMode>,
  );
}
