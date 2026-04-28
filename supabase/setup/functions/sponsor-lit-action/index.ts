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

  try {
    const { idToken, room_id, user_id } = await req.json()

    if (!idToken || !room_id) {
      throw new Error('Missing required parameters: idToken or room_id')
    }

    const messageToSign = `UNLOCK_SILO_${room_id}`

    // Fetch config from environment variables (with default fallback for Client ID)
    const masterClientId = Deno.env.get('MASTER_GOOGLE_CLIENT_ID') || '916762692506-4ki7iotmo0nh4g9rufvq57aessdb1k6q.apps.googleusercontent.com'
    const litApiKey = Deno.env.get('LIT_API_KEY')
    const pkpAddress = Deno.env.get('LIT_PKP_PUBLIC_KEY')
    const siloUrl = Deno.env.get('SUPABASE_URL') 

    if (!litApiKey) throw new Error('LIT_API_KEY missing in env')
    if (!pkpAddress) throw new Error('LIT_PKP_PUBLIC_KEY missing in env')
    if (!siloUrl) throw new Error('SUPABASE_URL missing in env')

    // The Decentralized Lit Action Code
    const litActionCode = `
    const _idToken = ${JSON.stringify(idToken)};
    const _masterId0 = ${JSON.stringify(masterClientId)};
    const _messageToSign = ${JSON.stringify(messageToSign)};
    const _pkpId = ${JSON.stringify(pkpAddress)};
    const _siloUrl = ${JSON.stringify(siloUrl)};
    const _roomId = ${JSON.stringify(room_id)};
    const _userId = ${JSON.stringify(user_id)};

    async function main() {
      try {
        // STEP 1: LIT INDEPENDENT IDENTITY CHECK
        const tokenResponse = await fetch('https://oauth2.googleapis.com/tokeninfo?access_token=' + _idToken);

        if (!tokenResponse.ok) {
          return { error: "Unauthorized: Invalid token lookup" };
        }

        const tokenData = await tokenResponse.json();
        
        if ((tokenData.aud !== _masterId0 && tokenData.azp !== _masterId0) || 
            !tokenData.exp || 
            tokenData.exp < Math.floor(Date.now() / 1000)) {
          return { error: "Unauthorized: Token claims invalid or expired" };
        }

        // STEP 2: ORACLE VERIFICATION
        const verifyUrl = _siloUrl + '/functions/v1/verify-membership';
        
        const verifyResponse = await fetch(verifyUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            idToken: _idToken,
            room_id: _roomId,
            user_id: _userId
          })
        });

        if (!verifyResponse.ok) {
          const errText = await verifyResponse.text();
          return { error: "Silo Verification Failed (" + verifyResponse.status + "): " + errText };
        }

        const verifyData = await verifyResponse.json();

        if (verifyData.isMember !== true) {
          return { error: "Access Denied: User is not an active member of this secure room" };
        }

        // STEP 3: SIGN AND RETURN KEY
        const wallet = new ethers.Wallet(
          await Lit.Actions.getPrivateKey({ pkpId: _pkpId })
        );
        const signature = await wallet.signMessage(_messageToSign);

        return { success: true, signature };

      } catch (error) {
        return { error: "Unauthorized: Execution failure (" + error.message + ")" };
      }
    }
    `;

    const litExecuteUrl = Deno.env.get('LIT_EXECUTE_API_URL') || 'https://api.chipotle.litprotocol.com/core/v1/lit_action'

    // Execute on the Lit Network
    const litResponse = await fetch(litExecuteUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Api-Key': litApiKey
      },
      body: JSON.stringify({ code: litActionCode })
    })

    if (!litResponse.ok) {
      const errorText = await litResponse.text()
      throw new Error(`Failed to execute Lit Action: ${errorText}`)
    }

    const litData = await litResponse.json()
    const parsedResponse = litData.response || litData.data?.response || litData

    if (parsedResponse.error) {
      throw new Error(parsedResponse.error)
    }

    if (!parsedResponse.signature) {
      throw new Error("Lit Action succeeded but did not return a signature")
    }

    return new Response(
      JSON.stringify({ success: true, signature: parsedResponse.signature }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error: any) {
    console.error('Edge Function Error:', error.message)
    return new Response(
      JSON.stringify({ error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    )
  }
})
