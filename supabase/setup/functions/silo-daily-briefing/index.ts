import { createClient } from "npm:@supabase/supabase-js@2";
import { GoogleGenAI } from "npm:@google/genai";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function generateDailyBriefing(messages: any[], languageCode: string = 'en') {
  const apiKey = Deno.env.get("GEMINI_API_KEY");

  if (!apiKey) {
    throw new Error("Server configuration error: Missing GEMINI_API_KEY");
  }

  const ai = new GoogleGenAI({ apiKey });

  // Map locale codes to full language names for better LLM comprehension
  const languageMap: Record<string, string> = {
    'km': 'Khmer',
    'en': 'English',
    'fr': 'French',
    'es': 'Spanish',
    'zh': 'Chinese',
    'ja': 'Japanese',
    'ko': 'Korean'
    // Add any other languages your app supports here
  };
  
  const targetLanguage = languageMap[languageCode] || 'English';

  const systemPrompt = `You are an elite Chief of Staff AI designed to summarize highly professional B2B communications.
Your task is to synthesize the provided JSON array of chat messages into a highly readable, concise "Daily Briefing." 

CRITICAL LANGUAGE INSTRUCTION:
You MUST generate the entire response (both the "title" and the "content") natively in ${targetLanguage}. Do not use English unless quoting a specific technical term. Ensure the markdown headers below are also translated into ${targetLanguage}.

Strict Formatting Rules:
1. Do not greet the user or write an introduction. Start immediately with the facts.
2. Group the summary logically by topic, NOT strictly chronologically.
3. Use the following Markdown structure:
   - **🔴 Urgent / Action Required:** (If none, omit this section).
   - **📌 Key Decisions:** (What was agreed upon).
   - **📝 General Updates:** (Brief bullet points).
4. Always attribute information to the specific person who said it.
5. Keep it incredibly concise.
6. Format: Return ONLY a valid JSON object with the keys "title" and "content" (Markdown allowed).`;

  const combinedText = `${systemPrompt}\n\nHere are the messages to summarize:\n${JSON.stringify(messages)}`;

  const response = await ai.models.generateContent({
    model: "gemini-3-flash-preview", // Note: Ensure you are using the correct model version for your SDK
    contents: combinedText,
  });

  return response.text;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        ...corsHeaders,
        "Content-Type": "text/plain",
        "Connection": "keep-alive",
      },
    });
  }

  try {
    let reqBody: any = {}
    try {
      if (req.body) {
        reqBody = await req.json()
      }
    } catch (e) {
      // Ignore JSON parse errors if body is empty
    }
    const targetLanguage = reqBody.language || 'en';

    // 1. Extract the User ID directly from the JWT payload
    const authHeader = req.headers.get("Authorization");

    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Unauthorized. Missing JWT in Authorization header." }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    
    // Decode the middle part of the JWT to get the user's ID (the 'sub' claim)
    const payloadBase64Url = token.split('.')[1];
    const payloadBase64 = payloadBase64Url.replace(/-/g, '+').replace(/_/g, '/');
    const decodedPayload = JSON.parse(atob(payloadBase64));
    const userId = decodedPayload.sub;

    // 2. Initialize Supabase Client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        global: {
          headers: {
            Authorization: authHeader,
          },
        },
      }
    );

    // 3a. Find all rooms the user is a member of
    // 🚨 IMPORTANT: Change 'room_participants' if your table is named differently
    const { data: userRooms, error: roomsError } = await supabase
      .from("room_participants")
      .select("room_id")
      .eq("user_id", userId);

    if (roomsError) {
      console.error("Database Error (Fetching Rooms):", roomsError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch user room memberships." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!userRooms || userRooms.length === 0) {
       return new Response(
        JSON.stringify({ summary: "You are not currently a member of any rooms." }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Extract an array of just the room IDs
    const roomIds = userRooms.map(room => room.room_id);

    // 3b. Query messages from ONLY those specific rooms
    const today = new Date().toISOString().split('T')[0];
    const { data: existing } = await supabase
      .from('ai_briefing_logs')
      .select('*')
      .eq('user_id', userId)
      .eq('briefing_date', today)
      .maybeSingle()

    if (existing) {
      return new Response(JSON.stringify(existing), { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      })
    }

    // 4. Data Aggregation (Filter: !Vault, !E2EE, Active Membership)
    const last24h = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
    
    const { data: messages, error: msgError } = await supabase
      .from('chat_messages')
      .select(`
          content,
          created_at,
          profiles!chat_messages_user_id_fkey(display_name, full_name),
          chat_rooms!inner(name, is_personal_vault, is_e2ee,
          room_participants!inner(user_id, status))`
      )
      .eq('chat_rooms.room_participants.user_id', userId)
      .eq('chat_rooms.room_participants.status', 'active')
      .eq('chat_rooms.is_personal_vault', false)
      .eq('chat_rooms.is_e2ee', false)
      .gte('created_at', last24h)
      .order('created_at', { ascending: true })

    if (msgError) throw msgError

    if (!messages || messages.length === 0) {
      return new Response(JSON.stringify({ 
        title: "No updates today", 
        content: "No significant activity found in your monitored rooms in the last 24 hours." 
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }
    
    // 4. Generate the AI Summary
    const textResponse = await generateDailyBriefing(messages, targetLanguage);
    // Clean up potential markdown code blocks in the response
    const cleanJson = textResponse.match(/\{[\s\S]*\}/)?.[0] || textResponse
    const briefingData = JSON.parse(cleanJson)

    // 6. Save & Return
    const { data: logEntry, error: insertError } = await supabase
      .from('ai_briefing_logs')
      .insert({
        user_id: userId,
        title: briefingData.title,
        content: briefingData.content,
        briefing_date: today
      })
      .select()
      .single()

    if (insertError) throw insertError

    return new Response(JSON.stringify(logEntry), { 
      headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
    })
    
  } catch (error: any) {
    console.error("Function Error:", error);
    return new Response(
      JSON.stringify({ error: error?.message || "An internal server error occurred." }),
      {
        status: 500,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      }
    );
  }
});
