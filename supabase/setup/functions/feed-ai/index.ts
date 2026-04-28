import { createClient } from 'npm:@supabase/supabase-js@2'
import { Buffer } from 'node:buffer'
import { resolvePDFJS } from 'https://esm.sh/pdfjs-serverless@0.4.2'

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
    const { roomId, messageId, filePath, bucketName, textContent, userId } = await req.json()

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Supabase credentials not configured')
    }
    const supabase = createClient(supabaseUrl, supabaseKey)

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
