import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || import.meta.env.SUPABASE_URL || 'https://tmfkfshciqozvxzuhnsp.supabase.co';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || import.meta.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRtZmtmc2NoaXFvenZ4enVobnNwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM3MDQ4MTQsImV4cCI6MjEwOTI4MDgxNH0.QlVRBq6u8LAfRikXdLykSYXVTQpgEaNODSW-ZdBzq9U';

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
});
