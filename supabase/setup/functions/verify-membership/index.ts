import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { idToken, room_id, user_id } = await req.json()

    if (!idToken || !room_id || !user_id) {
      throw new Error('Missing required verification parameters')
    }

    // 1. Verify the Google idToken to prevent unauthenticated spoofing
    const masterClientId = Deno.env.get('MASTER_GOOGLE_CLIENT_ID') || '916762692506-4ki7iotmo0nh4g9rufvq57aessdb1k6q.apps.googleusercontent.com'

    const tokenResponse = await fetch(`https://oauth2.googleapis.com/tokeninfo?access_token=${idToken}`)
    if (!tokenResponse.ok) {
      throw new Error('Unauthorized: Invalid Google token')
    }

    const tokenData = await tokenResponse.json()
    
    // Ensure the token belongs to the CamboVerse ecosystem and is not expired
    if ((tokenData.aud !== masterClientId && tokenData.azp !== masterClientId) || 
        !tokenData.exp || 
        tokenData.exp < Math.floor(Date.now() / 1000)) {
      throw new Error('Unauthorized: Token claims invalid or expired')
    }

    // 2. Initialize Supabase Admin Client to bypass RLS internally
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error('Silo Database configuration missing')
    }

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { persistSession: false }
    })

    // 3. Query the room_participants table securely
    const { data, error } = await supabaseAdmin
      .from('room_participants')
      .select('room_id')
      .eq('room_id', room_id)
      .eq('user_id', user_id)
      .eq('status', 'active')

    if (error) {
      throw new Error(`Database error: ${error.message}`)
    }

    // 4. Return the definitive boolean answer
    const isMember = data && data.length > 0

    return new Response(
      JSON.stringify({ isMember }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error: any) {
    console.error('Verification Error:', error.message)
    return new Response(
      JSON.stringify({ error: error.message, isMember: false }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    )
  }
})
