import { createClient } from 'npm:@supabase/supabase-js@2.39.3'
import { SignJWT } from 'npm:jose@5.2.0'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// 🌍 DEFAULT HUB CONFIGURATION
const DEFAULT_HUB_URL = 'https://hub.normsar.io'
const DEFAULT_HUB_PUBLISHABLE_KEY =
  'sb_publishable_yvy7GSQEldxhg_xD0l6F3g_x1st3Gjh'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { ticket_id } = await req.json()
    if (!ticket_id) {
      return new Response(
        JSON.stringify({ error: 'Missing ticket_id' }),
        { status: 400, headers: corsHeaders },
      )
    }

    // 1. Resolve Hub Credentials
    const hubUrl = Deno.env.get('HUB_URL') || DEFAULT_HUB_URL
    const hubKey =
      Deno.env.get('HUB_PUBLISHABLE_KEY') ||
      Deno.env.get('HUB_ANON_KEY') ||
      DEFAULT_HUB_PUBLISHABLE_KEY

    // 2. Initialize the client using the resolved Hub credentials
    const hubClient = createClient(hubUrl, hubKey)

    // 3. Redeem the ticket at the resolved Hub
    // NOTE: This RPC on the Hub must delete/invalidate the ticket immediately!
    const { data: hubData, error: redeemError } = await hubClient.rpc(
      'redeem_silo_ticket',
      {
        p_ticket_id: ticket_id,
      },
    )

    if (redeemError || !hubData) {
      return new Response(
        JSON.stringify({ error: 'Invalid or expired ticket' }),
        { status: 401, headers: corsHeaders },
      )
    }

    // 4. Get the native Silo JWT Secret
    const siloSecretString = Deno.env.get('SILO_JWT_SECRET')
    if (!siloSecretString) throw new Error('Missing Silo Secret in Environment')

    // 5. Mint the new JWT with strict PostgREST compliance
    const secret = new TextEncoder().encode(siloSecretString)

    const jwt = await new SignJWT({
      aud: 'authenticated',
      role: 'authenticated',
      sub: hubData.user_id,
      email: hubData.email,
      session_id: crypto.randomUUID(), // Required by Supabase GoTrue checks
      aal: 'aal1', // Required by Supabase GoTrue checks
      is_anonymous: false, // Required by Supabase GoTrue checks
      app_metadata: {
        provider: 'hub_ticket',
        silo_id: hubData.silo_id,
        silo_role: hubData.role,
      },
    })
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setIssuedAt()
      .setExpirationTime('15m') // Short-lived token for security
      .sign(secret)

    return new Response(JSON.stringify({ token: jwt }), {
      status: 200,
      headers: corsHeaders,
    })
  } catch (error) {
    console.error('Auth Edge Function Error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal Server Error' }),
      { status: 500, headers: corsHeaders },
    )
  }
})
