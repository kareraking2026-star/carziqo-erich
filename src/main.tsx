import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import SetupNeeded from './components/SetupNeeded';
import './index.css';

const root = createRoot(document.getElementById('root')!);

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
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
