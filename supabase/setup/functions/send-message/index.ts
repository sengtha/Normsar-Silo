import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  // 1. CORS Configuration
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
        'Access-Control-Allow-Methods': 'POST, OPTIONS'
      },
    });
  }

  try {
    // ⚡ CHANGED: Expect the Action-Based payload structure
    const { action, room_id, payload } = await req.json();

    // 2. Initialize Supabase Admin Client (Service Role Key)
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // 3. Extract the User ID directly from the JWT payload (Ultra-fast edge auth)
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) throw new Error('Missing Authorization header');

    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    
    // Decode the middle part of the JWT to get the user's ID (the 'sub' claim)
    const payloadBase64Url = token.split('.')[1];
    const payloadBase64 = payloadBase64Url.replace(/-/g, '+').replace(/_/g, '/');
    const decodedPayload = JSON.parse(atob(payloadBase64));
    const userId = decodedPayload.sub;

    if (!userId) throw new Error('Invalid token payload');

    // Create a client that uses this specific user's token
    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    );

    // 4. Verify Membership AND Token Validity simultaneously
    const { data: participant, error: participantError } = await supabaseUser
      .from("room_participants")
      .select("room_id")
      .eq("room_id", room_id)
      .eq("user_id", userId)
      .eq("status", "active")
      .single();

    if (participantError) {
      console.error("Auth/Participant error:", participantError);
      throw new Error("Unauthorized token or you are not an active member of this room");
    }

    // 4.5 Fetch the room's transport routing preference
    const { data: roomInfo } = await supabaseAdmin
      .from('chat_rooms')
      .select('websocket_transport')
      .eq('id', room_id)
      .single();
      
    const transportType = roomInfo?.websocket_transport || 'supabase';

    // 5. THE ROUTER: Perform the correct database mutation based on Action
    let broadcastData = null;

    switch (action) {
      case 'NEW_MESSAGE': {
        const { data, error } = await supabaseAdmin
          .from("chat_messages")
          .insert({ 
            room_id: room_id, 
            user_id: userId, 
            ...payload // Spreads id, content, tags, attachments, metadata, etc.
          })
          .select("*, profiles(full_name, avatar_url)")
          .single();
        if (error) throw error;
        broadcastData = data;
        break;
      }

      case 'ADD_REACTION': {
        const { data, error } = await supabaseAdmin
          .from('message_reactions')
          .insert({ 
            message_id: payload.message_id, 
            user_id: userId, 
            emoji: payload.emoji 
          })
          .select()
          .single();
        if (error) throw error;
        broadcastData = data;
        break;
      }

      case 'EDIT_MESSAGE': {
        // 🔒 Ensures they can only edit their own messages
        const { data, error } = await supabaseAdmin
          .from('chat_messages')
          .update({ content: payload.content, key_version: payload.key_version })
          .eq('id', payload.message_id)
          .eq('user_id', userId)
          .select('*, profiles(full_name, avatar_url)')
          .single();
        if (error) throw error;
        broadcastData = data;
        break;
      }

      case 'DELETE_MESSAGE': {
        // 🔒 Ensures they can only delete their own messages
        const { error } = await supabaseAdmin
          .from('chat_messages')
          .delete()
          .eq('id', payload.message_id)
          .eq('user_id', userId);
        if (error) throw error;
        
        broadcastData = { id: payload.message_id };
        break;
      }
         case 'TOGGLE_PIN': {
        const { data, error } = await supabaseAdmin
          .from('chat_messages')
          .update({ is_pinned: payload.is_pinned })
          .eq('id', payload.message_id)
          .select('id, is_pinned')
          .single();
        if (error) throw error;
        broadcastData = data;
        break;
      }

      case 'TOGGLE_FORWARDING': {
        const { data, error } = await supabaseAdmin
          .from('chat_messages')
          .update({ allow_forwarding: payload.allow_forwarding })
          .eq('id', payload.message_id)
          .select('id, allow_forwarding')
          .single();
        if (error) throw error;
        broadcastData = data;
        break;
      }

      case 'REMOVE_REACTION': {
        const { error } = await supabaseAdmin
          .from('message_reactions')
          .delete()
          .eq('message_id', payload.message_id)
          .eq('emoji', payload.emoji)
          .eq('user_id', userId);
        if (error) throw error;
        broadcastData = { message_id: payload.message_id, emoji: payload.emoji, user_id: userId };
        break;
      }

      default:
        throw new Error(`Unknown action type: ${action}`);
    }

    // 6. THE MAGIC: Dynamic Transport Routing
    if (transportType === 'cloudflare') {
      
      let cfBaseUrl = Deno.env.get('CF_DO_URL');
      const doSecretKey = Deno.env.get('CF_DO_SECRET_KEY');

      if (!cfBaseUrl || !doSecretKey) {
        throw new Error('Server configuration error: Missing Cloudflare DO URL or Secret Key');
      }

      cfBaseUrl = cfBaseUrl.endsWith('/') ? cfBaseUrl.slice(0, -1) : cfBaseUrl;
      const cfUrl = `${cfBaseUrl}/room/${room_id}`;

      const cfResponse = await fetch(cfUrl, {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          'X-DO-Access-Key': doSecretKey 
        },
        body: JSON.stringify({
          type: 'broadcast',
          event: action, // ⚡ Broadcasts the specific action
          payload: broadcastData // ⚡ Broadcasts the resulting data
        })
      });

      if (!cfResponse.ok) {
        console.error('Cloudflare broadcast failed:', await cfResponse.text());
      }

    } else {
      
      const channel = supabaseAdmin.channel(`room:${room_id}`);
      await channel.send({
        type: "broadcast",
        event: action, // ⚡ Broadcasts the specific action
        payload: broadcastData, // ⚡ Broadcasts the resulting data
      });
      
      await supabaseAdmin.removeChannel(channel);
    }

    // 7. Return Success
    return new Response(JSON.stringify({ success: true, data: broadcastData }), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 400,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  }
});
