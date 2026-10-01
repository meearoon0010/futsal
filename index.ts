// Supabase Edge Function: admin-reset-password
//
// Lets the app's single admin set a new password for any player's
// account directly — for players who forgot their password, or who
// signed up with an email they don't actually have access to (so the
// normal "forgot password" email link can never reach them).
//
// WHY THIS HAS TO BE AN EDGE FUNCTION:
// Changing another user's password requires Supabase's admin API
// (`auth.admin.updateUserById`), which only works with the SERVICE ROLE
// key. That key must never be placed in index.html or any other
// client-side code — anyone could read it from "view source" and take
// over the entire project. This function keeps that key on the server
// side only, and only acts after confirming the caller is the admin.
//
// DEPLOY (from your project root, with the Supabase CLI installed and
// `supabase login` / `supabase link` already done):
//   supabase functions deploy admin-reset-password
//
// Supabase automatically provides SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY as environment variables to every Edge
// Function — you don't need to set those yourself.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ADMIN_EMAIL = 'whitewalkerofnorth@gmail.com';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  try {
    const authHeader = req.headers.get('Authorization') || '';
    const callerToken = authHeader.replace(/^Bearer\s+/i, '');
    if (!callerToken) {
      return jsonResponse({ error: 'Missing authorization' }, 401);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse({ error: 'Function is missing its Supabase environment variables' }, 500);
    }
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    // Confirm the caller is signed in, and is specifically the admin —
    // nobody else is allowed to call this, no matter what user_id they pass.
    const { data: callerData, error: callerError } = await adminClient.auth.getUser(callerToken);
    if (callerError || !callerData?.user) {
      return jsonResponse({ error: 'Invalid or expired session — sign in again' }, 401);
    }
    const callerEmail = (callerData.user.email || '').toLowerCase();
    if (callerEmail !== ADMIN_EMAIL.toLowerCase()) {
      return jsonResponse({ error: 'Only the admin can reset passwords' }, 403);
    }

    const payload = await req.json().catch(() => ({}));
    const { user_id, new_password } = payload as { user_id?: string; new_password?: string };

    if (!user_id || typeof user_id !== 'string') {
      return jsonResponse({ error: 'Missing user_id' }, 400);
    }
    if (!new_password || typeof new_password !== 'string' || new_password.length < 6) {
      return jsonResponse({ error: 'Password must be at least 6 characters' }, 400);
    }

    const { error: updateError } = await adminClient.auth.admin.updateUserById(user_id, {
      password: new_password,
    });
    if (updateError) {
      return jsonResponse({ error: updateError.message }, 400);
    }

    return jsonResponse({ success: true });
  } catch (err) {
    return jsonResponse({ error: String((err as Error)?.message || err) }, 500);
  }
});
