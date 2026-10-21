// =============================================================================
// BMC Finals Project - student_shop
// `xendit-webhook` edge function
//
// Xendit calls this url when an invoice was paid. The function verifies the
// callback token, then flips the order to PAID.
//
// The order is written with the SERVICE ROLE key, so neither the app nor a
// third party can mark an order as paid without a confirmed Xendit payment.
//
// Xendit sends the token in the `x-callback-token` header; it has to be the
// same value as the XENDIT_WEBHOOK_TOKEN secret.
// =============================================================================

import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-callback-token',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const expectedToken = Deno.env.get('XENDIT_WEBHOOK_TOKEN') ?? '';
  const receivedToken = req.headers.get('x-callback-token') ?? '';

  if (!expectedToken || receivedToken !== expectedToken) {
    console.warn('the webhook was called without a valid callback token');
    return json({ error: 'Unauthorized webhook caller' }, 401);
  }

  let payload: {
    external_id?: string;
    id?: string;
    status?: string;
    paid_at?: string;
  };
  try {
    payload = await req.json();
  } catch {
    return json({ error: 'The request body is not valid JSON.' }, 400);
  }

  const externalId = String(payload.external_id ?? '').trim();
  if (!externalId) {
    return json({ error: 'external_id is required' }, 400);
  }

  const isPaid = String(payload.status ?? '').toUpperCase() === 'PAID';
  if (!isPaid) {
    // nothing to do - the order stays PENDING
    return json({ received: true, updated: false });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey =
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY') ?? '';

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { error } = await admin
    .from('orders')
    .update({ status: 'PAID' })
    .eq('external_id', externalId);

  if (error) {
    console.error('the order could not be updated', error);
    return json({ error: 'The order could not be updated.' }, 500);
  }

  console.log(`order ${externalId} is now PAID`);
  return json({ received: true, updated: true, external_id: externalId });
});
