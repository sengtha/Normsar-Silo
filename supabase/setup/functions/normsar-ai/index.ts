import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// The fixed ID we created in SQL for the AI
const NORMSAR_AI_USER_ID = '00000000-0000-0000-0000-000000000000'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    
    const body = await req.json()
    const roomId = body.roomId || body.room_id
    const prompt = body.prompt
    const messageId = body.messageId || body.message_id

    // 2. Add an early validation check
    if (!roomId) {
      throw new Error("Missing 'roomId' in request body.")
    }
    
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    const apiKey = Deno.env.get('GEMINI_API_KEY')

    if (!supabaseUrl || !supabaseKey || !apiKey) {
      throw new Error('Server configuration missing')
    }

    const supabase = createClient(supabaseUrl, supabaseKey)

    // 1. Clean the prompt (remove the @normsar tag)
    const cleanPrompt = String(prompt ?? '').replace(/@normsar/gi, '').trim()

    // 2. Embed the User's Question
    const embedUrl = `https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent?key=${apiKey}`
    const embedRes = await fetch(embedUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'models/gemini-embedding-001',
        content: { parts: [{ text: cleanPrompt }] },
        outputDimensionality: 768,
      }),
    })

    if (!embedRes.ok) {
      const errText = await embedRes.text()
      console.error('Gemini Embedding Error:', errText)
      throw new Error(`Embedding API Error: ${errText}`)
    }

    const embedData = await embedRes.json()
    const queryEmbedding = embedData?.embedding?.values

    if (!Array.isArray(queryEmbedding)) {
      throw new Error('Embedding API returned unexpected format')
    }

    // 3. Search the Vector Database (RAG)
    const { data: matchedDocs, error: matchError } = await supabase.rpc('match_doc_segments', {
      query_embedding: queryEmbedding,
      match_threshold: 0.65,
      match_count: 5,
      p_room_id: roomId,
    })

    if (matchError) throw matchError

    // 4. Build the Context String
    let contextText =
      "No specific document context found for this room. Answer based on general knowledge."

    if (matchedDocs && (matchedDocs as any[]).length > 0) {
      contextText = (matchedDocs as any[]).map((doc) => doc.content).join('\n\n---\n\n')
    }

    // 5. Construct the Gemini AI Prompt
    const systemInstruction = `You are Normsar AI, a helpful and highly intelligent assistant in a collaborative workspace. \nUsers will ask you questions. You must base your answer strictly on the provided 'Room Context' if it is relevant. \nIf the context does not contain the answer, state that you cannot find it in the room's documents, and then provide your best general knowledge answer. Format your response cleanly using Markdown.`

    const finalPrompt = `Room Context:\n${contextText}\n\nUser Question:\n${cleanPrompt}`

    // 6. Generate the Answer
    const generateUrl = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`
    const generateRes = await fetch(generateUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemInstruction }] },
        contents: [{ role: 'user', parts: [{ text: finalPrompt }] }],
        generationConfig: { temperature: 0.3 },
      }),
    })

    // --- IMPROVED ERROR CATCHING ---
    if (!generateRes.ok) {
      const errorText = await generateRes.text()
      console.error('Gemini Generation Error:', errorText)
      throw new Error(`Gemini API Error (${generateRes.status}): ${errorText}`)
    }
    // -------------------------------

    const generateData = await generateRes.json()

    // Safety check in case Google blocks the prompt for safety reasons
    const aiAnswer =
      generateData?.candidates?.[0]?.content?.parts?.[0]?.text ?? null

    if (!aiAnswer) {
      console.error('Unexpected Gemini Payload:', generateData)
      throw new Error('Gemini returned an empty response. The prompt might have triggered a safety filter.')
    }

    // 7. Insert the AI's response back into the Chat Room
    const { error: insertError } = await supabase
      .from('chat_messages')
      .insert({
        room_id: roomId,
        user_id: NORMSAR_AI_USER_ID,
        content: aiAnswer,
        reply_to_message_id: messageId || null,
      })

    if (insertError) throw insertError

    return new Response(JSON.stringify({ status: 'success' }), {
      status: 200,
      headers: corsHeaders,
    })
  } catch (error: any) {
    console.error('Normsar AI Error:', error)
    return new Response(JSON.stringify({ error: error?.message || String(error) }), {
      status: 500,
      headers: corsHeaders,
    })
  }
})
