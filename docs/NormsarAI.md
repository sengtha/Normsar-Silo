# 🤖 Enabling Normsar AI (Bring Your Own AI)

Your Normsar Silo includes a powerful, built-in RAG (Retrieval-Augmented Generation) AI assistant. By connecting your own Google Gemini API key, you can feed documents directly into your chat rooms and interact with them securely. 

**Supported Document Formats:** `.pdf`, `.md`, `.csv`, `.txt` (Max size: 3MB per file)

Follow these steps to generate your API key and link it to your sovereign infrastructure.

---

### Step 1: Get Your Gemini API Key from Google
You will need an API key from Google AI Studio to power the intelligence of your Silo. The free tier is excellent for personal and community use.

1. Go to [Google AI Studio](https://aistudio.google.com/app/apikey).
2. Sign in with your Google account.
3. In the left-hand menu, click on **Get API key**.
4. Click the **Create API key** button.
5. Choose to create the key in a new or existing Google Cloud project.
6. Once generated, **copy your API key**. Keep this secret and secure!

### Step 2: Add the API Key to Your Supabase Silo
Now, you need to securely store this key in your Supabase infrastructure so your Edge Functions can use it to read and embed your documents.

1. Go to your **Supabase Dashboard** and open your Silo project.
2. Navigate to **Edge Functions** in the left-hand sidebar.
3. Click on **Manage Secrets** (usually located in the top right of the Edge Functions page).
4. Click **Add New Secret**:
   - **Name:** `GEMINI_API_KEY`
   - **Value:** Paste the API key you copied from Google AI Studio.
5. Click **Save**.

---

### 🎉 You're Ready!
Your Normsar AI is now active. You can start uploading supported documents directly into your chat rooms. The Edge Functions will securely chunk the text, embed it into your `doc_segments` vector database, and allow you to ask context-aware questions right within the chat!
