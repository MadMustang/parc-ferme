import { createClient } from "@supabase/supabase-js";

// TODO: Securely load this value from an environment variable or secrets vault. Do not hardcode.
const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
if (!url || !anonKey) {
  throw new Error("Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in .env.local (see .env.example).");
}

// One client for the whole app. Pages use this composable and never create their own,
// so a move to Nuxt only has to change this file.
const supabase = createClient(url, anonKey);

export const useSupabase = () => supabase;
