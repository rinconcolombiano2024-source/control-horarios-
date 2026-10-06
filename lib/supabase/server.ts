import {
  createClient,
  type SupabaseClient,
  type SupabaseClientOptions,
} from "@supabase/supabase-js";

export interface SupabaseServerClientConfig {
  url: string;
  anonKey: string;
  accessToken?: string;
}

function requireNonEmptyString(value: string, name: string): string {
  const normalized = value.trim();

  if (!normalized) {
    throw new Error(`Missing ${name}`);
  }

  return normalized;
}

function normalizeAccessToken(
  accessToken: string | undefined,
): string | undefined {
  const normalized = accessToken?.trim();

  return normalized || undefined;
}

/**
 * Creates a Supabase client intended exclusively for trusted server-side code.
 *
 * Important:
 * - This function does not read process.env directly.
 * - Runtime/environment configuration must be injected by the caller.
 * - Service-role keys must NEVER be passed to browser code.
 * - User authorization continues to be enforced by Supabase RLS.
 */
export function createSupabaseServerClient(
  config: SupabaseServerClientConfig,
): SupabaseClient {
  if (typeof window !== "undefined") {
    throw new Error(
      "createSupabaseServerClient must not be executed in a browser context",
    );
  }

  const url = requireNonEmptyString(config.url, "Supabase URL");
  const anonKey = requireNonEmptyString(config.anonKey, "Supabase anon key");
  const accessToken = normalizeAccessToken(config.accessToken);

  const options: SupabaseClientOptions<"public"> = {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  };

  if (accessToken) {
    options.global = {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    };
  }

  return createClient(url, anonKey, options);
}
