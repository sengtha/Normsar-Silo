
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // Check if the Silo admin has configured their sovereign Lit keys
  const litApiKey = Deno.env.get('LIT_API_KEY')
  const pkpAddress = Deno.env.get('LIT_PKP_PUBLIC_KEY')

  const isConfigured = !!(litApiKey && pkpAddress)

  return new Response(
    JSON.stringify({ isConfigured }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
  )
})
