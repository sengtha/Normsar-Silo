import { createClient } from 'npm:@supabase/supabase-js@2'
import { Buffer } from 'node:buffer'
import { resolvePDFJS } from 'https://esm.sh/pdfjs-serverless@0.4.2'

// The caller must be an active participant of the room. Silo sessions are
// JWTs minted by authenticate-hub-user with no auth.users row, so
// auth.getUser() can't check them; PostgREST verifies the signature, so a
// membership query made with the caller's token doubles as verification.
// Returns the caller's user id, or null.
async function authorizeRoomMember(req: Request, roomId: unknown): Promise<string | null> {
  if (typeof roomId !== 'string' || !roomId) return null
  const authHeader = req.headers.get('Authorization') ?? ''
  const token = authHeader.replace(/^Bearer\s+/i, '').trim()
  let sub: unknown
  try {
    sub = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).sub
  } catch {
    return null
  }
  if (typeof sub !== 'string' || !sub) return null

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: `Bearer ${token}` } } },
  )
  const { data, error } = await userClient
    .from('room_participants')
    .select('room_id')
    .eq('room_id', roomId)
    .eq('user_id', sub)
    .eq('status', 'active')
    .maybeSingle()
  return !error && data ? sub : null
}

// Mirrors how the app derives (bucket, path) from an attachment URL
// (MessageBubble handleFeedAI), so a request can be matched to the message.
function storageLocation(url: string): { bucket: string; path: string } | null {
  try {
    const parts = new URL(url).pathname.split('/')
    const publicIndex = parts.indexOf('public')
    if (publicIndex !== -1 && parts.length > publicIndex + 2) {
      return { bucket: parts[publicIndex + 1], path: parts.slice(publicIndex + 2).join('/') }
    }
    return { bucket: 'silo_uploads', path: parts[parts.length - 1] }
  } catch {
    return null
  }
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { roomId, messageId, filePath, bucketName, textContent } = await req.json()

    // This function runs as the service role: it could download any file in
    // any bucket and add it to any room's AI context. Only a member of the
    // room may feed it, and only a file attached to a message in that room.
    const userId = await authorizeRoomMember(req, roomId)
    if (!userId) {
      return new Response(JSON.stringify({ error: 'Not a member of this room' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Supabase credentials not configured')
    }
    const supabase = createClient(supabaseUrl, supabaseKey)

    const { data: message } = await supabase
      .from('chat_messages')
      .select('id, attachments')
      .eq('id', messageId)
      .eq('room_id', roomId)
      .maybeSingle()
    const attached = filePath
      ? (message?.attachments ?? []).some((a: any) => {
          const loc = typeof a?.url === 'string' ? storageLocation(a.url) : null
          return loc?.bucket === bucketName && loc?.path === filePath
        })
      : true
    if (!message || !attached) {
      return new Response(JSON.stringify({ error: 'File not found in this room' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const apiKey = Deno.env.get('GEMINI_API_KEY')
    if (!apiKey) {
      return new Response(JSON.stringify({ error: 'Gemini API key not configured' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 1. Duplicate Check
    let existingQuery = supabase
      .from('doc_segments')
      .select('id')
      .eq('source_message_id', messageId)
      .limit(1)

    if (filePath) {
      existingQuery = existingQuery.eq('file_path', filePath)
    } else {
      existingQuery = existingQuery.is('file_path', null)
    }

    const { data: existing } = await existingQuery
    if (existing && existing.length > 0) {
      return new Response(JSON.stringify({ status: 'already_embedded' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    let textToProcess = textContent || ''

    // 2. File Download & Parsing
    if (filePath && bucketName) {
      const { data: fileData, error: downloadError } = await supabase.storage.from(bucketName).download(filePath)
      if (downloadError) throw downloadError

      const MAX_FILE_SIZE_MB = 4
      if (fileData.size > MAX_FILE_SIZE_MB * 1024 * 1024) {
        return new Response(
          JSON.stringify({ error: `File exceeds the maximum limit of ${MAX_FILE_SIZE_MB}MB.` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }

      const fileExt = filePath.toLowerCase()
      const arrayBuffer = await fileData.arrayBuffer()

      if (fileExt.endsWith('.pdf')) {
        // --- Serverless PDF parser ---
        const { getDocument } = await resolvePDFJS()
        const data = new Uint8Array(arrayBuffer)
        const doc = await getDocument({ data, useSystemFonts: true }).promise

        let pdfString = ''
        for (let pageNum = 1; pageNum <= doc.numPages; pageNum++) {
          const page = await doc.getPage(pageNum)
          const content = await page.getTextContent()
          const strings = content.items.map((item: any) => item.str)
          pdfString += strings.join(' ') + '\n'
        }
        textToProcess = pdfString
        // --------------------------------
      } else if (fileExt.endsWith('.csv') || fileExt.endsWith('.txt') || fileExt.endsWith('.md')) {
        textToProcess = await fileData.text()
      } else {
        // Reject all other file types
        return new Response(
          JSON.stringify({ error: 'Unsupported file type. Only .pdf, .md, .csv, and .txt are supported.' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
    }

    if (!textToProcess || textToProcess.trim().length === 0) {
      return new Response(JSON.stringify({ error: 'No readable text found in this file.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 3. Chunking text
    const chunkSize = 1000
    const overlap = 100
    const chunks: string[] = []
    let i = 0
    while (i < textToProcess.length) {
      chunks.push(textToProcess.slice(i, i + chunkSize))
      i += chunkSize - overlap
    }

    // 4. Gemini Embedding via REST API
    const recordsToInsert: any[] = []

    for (let index = 0; index < chunks.length; index++) {
      const chunkText = chunks[index]

      const apiUrl = `https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent?key=${apiKey}`

      const geminiResponse = await fetch(apiUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model: 'models/gemini-embedding-001',
          content: { parts: [{ text: chunkText }] },
          outputDimensionality: 768,
        }),
      })

      if (!geminiResponse.ok) {
        const errorText = await geminiResponse.text()
        throw new Error(`Gemini API Error (${geminiResponse.status}): ${errorText}`)
      }

      const responseData = await geminiResponse.json()
      const embedding = responseData.embedding.values

      recordsToInsert.push({
        room_id: roomId,
        content: chunkText,
        embedding: embedding,
        source_message_id: messageId,
        fed_by_user_id: userId,
        chunk_index: index,
        file_path: filePath || null,
      })
    }

    // 5. Database Insert
    const { error: insertError } = await supabase.from('doc_segments').insert(recordsToInsert)
    if (insertError) throw insertError

    return new Response(JSON.stringify({ status: 'success', chunks_processed: recordsToInsert.length }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error: any) {
    console.error('Error in feed-ai:', error)
    return new Response(JSON.stringify({ error: error?.message || String(error) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
