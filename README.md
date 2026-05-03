# Normsar-Silo
The self-hosted, decentralized data node for Normsar Sovereign Messaging. Deploy your own Silo to achieve true data sovereignty and connect securely to the Normsar Hub.

# 🚀 Silo Setup Guide

Follow these steps to deploy and register your own sovereign messaging node.

## Edge Function Secrets

To run the Silo Edge Functions properly, you must configure the following secrets in your Supabase project. 

You can set these via the Supabase Dashboard (Settings > Edge Functions) or using the Supabase CLI:
`supabase secrets set VARIABLE_NAME=value`

### 🔒 Required Secrets (Silo Core)
These secrets are mandatory for the Silo to function and authenticate correctly.

| Variable | Description |
| :--- | :--- |
| `SUPABASE_URL` | The REST API URL of your Supabase project. |
| `SUPABASE_ANON_KEY` | The anonymous public key for standard client requests. |
| `SUPABASE_SERVICE_ROLE_KEY` | The admin key used to bypass Row Level Security (RLS). **Keep this secure.** |
| `SILO_JWT_SECRET` | The secret used to sign and verify JSON Web Tokens (JWTs) for the Silo. |

### 🤖 Optional: AI Integration
Required only if you are enabling AI-assisted features.

| Variable | Description |
| :--- | :--- |
| `GEMINI_API_KEY` | Your Google Gemini API key for AI functionalities. |

### ☁️ Optional: Cloudflare Durable Objects
Required only if you are using Cloudflare Durable Objects for state management or WebSockets. https://github.com/sengtha/Normsar-DO 

| Variable | Description |
| :--- | :--- |
| `CF_DO_SECRET_KEY` | The secret key used to securely authenticate with your Durable Object. |
| `CF_DO_URL` | The endpoint URL where your Cloudflare Durable Object is hosted. |

### 🔐 Optional: End-to-End Encryption (E2EE)
Required only if you are implementing E2EE using the Lit Protocol network.

| Variable | Description |
| :--- | :--- |
| `LIT_PKP_PUBLIC_KEY` | The Programmable Key Pair (PKP) public key for Lit Protocol. |
| `LIT_API_KEY` | Your developer API key for accessing Lit Protocol services. |
---

### 1. Configure Edge Function Secrets
You must set a JWT secret to secure communication between your Silo and the Normsar network.
1. Go to your **Supabase Dashboard**.
2. Navigate to **Project Settings** -> **JWT Key**.
3. Under the **JWT Settings** section, copy the **JWT Secret** (Legacy JWT secret).
4. Go to **Edge Functions** -> **Manage Secrets** in the sidebar.
5. Click **Add New Secret**:
   - **Name:** `SILO_JWT_SECRET`
   - **Value:** Paste the JWT secret you copied in step 3.

### 2. Import Database Schema
Apply the core architecture, including AI vector support and governance logic.
1. Open the **SQL Editor** from the Supabase Dashboard menu.
2. Open the file: `supabase/setup/schema/normsar_silo_schema.sql`.
3. Copy the entire content of that SQL file.
4. Paste it into the Supabase SQL Editor and click **Run**.

### 3. Deploy Edge Functions
Deploy the logic required for AI processing and system automation.
1. Navigate to **Edge Functions** in your Supabase Dashboard.
2. Click **Deploy New Function** (Via Editor).
3. Create a function using the exact name found in the `supabase/setup/functions` folder.
4. Copy the code from the corresponding `index.ts` file and save it in the dashboard editor.

Set **Verify JWT with legacy secret** to **OFF** for each function. 

### 4. Register your Silo
Link your infrastructure to the Normsar ecosystem.
1. Go to [https://normsar.io/silo-manager](https://normsar.io/silo-manager) (Sign-in required).
2. Obtain your **Project URL** and **Anon Key** from **Project Search** in your Supabase Dashboard.
3. Input these credentials into the registration form.
4. Click **Register** to finalize your sovereign node.
