import { createClient } from 'npm:@supabase/supabase-js@2';

const allowedOrigins = new Set([
  'https://legendary-tanuki-cd4592.netlify.app',
  'http://127.0.0.1:5173',
  'http://localhost:5173',
]);

function corsHeaders(origin: string | null): HeadersInit {
  return {
    'Access-Control-Allow-Origin': origin && allowedOrigins.has(origin) ? origin : 'null',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}

function jsonResponse(body: unknown, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), 'Content-Type': 'application/json' },
  });
}

async function listUserFiles(
  admin: ReturnType<typeof createClient>,
  bucket: string,
  prefix = '',
): Promise<string[]> {
  const paths: string[] = [];
  const pageSize = 100;

  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await admin.storage.from(bucket).list(prefix, {
      limit: pageSize,
      offset,
      sortBy: { column: 'name', order: 'asc' },
    });
    if (error) throw error;
    const entries = data ?? [];
    for (const entry of entries) {
      const path = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.id) {
        paths.push(path);
      } else {
        paths.push(...await listUserFiles(admin, bucket, path));
      }
    }
    if (entries.length < pageSize) break;
  }
  return paths;
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get('Origin');
  const headers = corsHeaders(origin);
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers });
  }
  if (origin && !allowedOrigins.has(origin)) {
    return jsonResponse({ error: 'Origin not allowed.' }, 403, origin);
  }
  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed.' }, 405, origin);
  }

  const authorization = request.headers.get('Authorization');
  const token = authorization?.replace(/^Bearer\s+/i, '');
  if (!authorization || !token) {
    return jsonResponse({ error: 'Sign in to delete your account.' }, 401, origin);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceRoleKey) {
    return jsonResponse({ error: 'Account deletion is temporarily unavailable.' }, 500, origin);
  }

  const authClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: authData, error: authError } = await authClient.auth.getUser(token);
  const user = authData.user;
  if (authError || !user) {
    return jsonResponse({ error: 'Your session is invalid. Sign in again.' }, 401, origin);
  }

  const admin = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    for (const bucket of ['profile-photos', 'student-verification', 'listing-photos']) {
      const files = await listUserFiles(admin, bucket, user.id);
      for (let offset = 0; offset < files.length; offset += 100) {
        const { error } = await admin.storage.from(bucket).remove(files.slice(offset, offset + 100));
        if (error) throw error;
      }
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
    if (deleteError) throw deleteError;
    return jsonResponse({ deleted: true }, 200, origin);
  } catch (error) {
    console.error('Account deletion failed for authenticated user.', error);
    return jsonResponse({ error: 'We could not finish deleting your account. Please try again.' }, 500, origin);
  }
});
