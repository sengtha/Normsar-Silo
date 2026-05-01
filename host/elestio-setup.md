# 🚀 Normsar Silo Setup Guide (Elestio-Hosted Supabase)

This guide walks you through deploying and registering your sovereign messaging node on **Elestio**, a decentralized hosting platform for self-managed databases.

## Prerequisites

- Elestio account with an active Supabase instance running
- Normsar Silo repository cloned locally
- Basic familiarity with Elestio Dashboard and Supabase SQL Editor
- Access to environment secrets configuration

---

## 🔒 Edge Function Secrets Overview

To run the Silo Edge Functions properly, you must configure the following secrets in your Supabase project via Elestio. You can set these using:
1. **Elestio File Explorer** – Edit `keys.env` file
2. **Supabase Dashboard** (accessible from Elestio) – Set secrets directly

### Required Secrets (Silo Core)
These secrets are mandatory for the Silo to function and authenticate correctly.

| Variable | Description |
| :--- | :--- |
| `SUPABASE_URL` | The REST API URL of your Supabase instance on Elestio. |
| `SUPABASE_ANON_KEY` | The anonymous public key for standard client requests. |
| `SUPABASE_SERVICE_ROLE_KEY` | The admin key used to bypass Row Level Security (RLS). **Keep this secure.** |
| `SILO_JWT_SECRET` | The secret used to sign and verify JSON Web Tokens (JWTs) for the Silo. |

### Optional: AI Integration
Required only if you are enabling AI-assisted features.

| Variable | Description |
| :--- | :--- |
| `GEMINI_API_KEY` | Your Google Gemini API key for AI functionalities. |

### Optional: Cloudflare Durable Objects
Required only if you are using Cloudflare Durable Objects for state management or WebSockets.

| Variable | Description |
| :--- | :--- |
| `CF_DO_SECRET_KEY` | The secret key used to securely authenticate with your Durable Object. |
| `CF_DO_URL` | The endpoint URL where your Cloudflare Durable Object is hosted. |

### Optional: End-to-End Encryption (E2EE)
Required only if you are implementing E2EE using the Lit Protocol network.

| Variable | Description |
| :--- | :--- |
| `LIT_PKP_PUBLIC_KEY` | The Programmable Key Pair (PKP) public key for Lit Protocol. |
| `LIT_API_KEY` | Your developer API key for accessing Lit Protocol services. |

---

## Step 1: Access Your Elestio Supabase Instance

1. Log in to your **Elestio Dashboard** at [elestio.com](https://elestio.com)
2. Navigate to your Supabase service in the sidebar
3. Click **Open Service** to access your Supabase instance
4. You are now in the **Supabase Dashboard** hosted by Elestio

> **Note:** Your Supabase credentials (URL, ANON_KEY, SERVICE_ROLE_KEY) are available in **Project Settings > API** within the Supabase Dashboard.

---

## Step 2: Configure Edge Function Secrets Using Elestio File Explorer

### 2.1 Create a `keys.env` File Locally

Create a new file called `keys.env` in your repository root with all required secrets:

```env
# Core Supabase Credentials
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
SILO_JWT_SECRET=your-jwt-secret-key

# Optional: AI Integration
GEMINI_API_KEY=your-google-gemini-api-key

# Optional: Cloudflare Durable Objects
CF_DO_SECRET_KEY=your-cloudflare-do-secret
CF_DO_URL=https://your-durable-object.example.com

# Optional: Lit Protocol (E2EE)
LIT_PKP_PUBLIC_KEY=your-lit-pkp-public-key
LIT_API_KEY=your-lit-api-key
```

### 2.2 Retrieve Your Credentials from Supabase

1. In the **Supabase Dashboard** (via Elestio):
   - Navigate to **Project Settings** > **API**
   - Copy your **Project URL** (for `SUPABASE_URL`)
   - Copy your **Anon Key** (for `SUPABASE_ANON_KEY`)
   - Copy your **Service Role Key** (for `SUPABASE_SERVICE_ROLE_KEY`)

2. For **SILO_JWT_SECRET**:
   - Under **JWT Settings**, copy the **JWT Secret** (Legacy JWT secret)

### 2.3 Upload `keys.env` via Elestio File Explorer

1. Return to your **Elestio Dashboard**
2. Click on your **Supabase service**
3. Go to **File Manager** (or **File Explorer**)
4. Navigate to the root directory of your Supabase instance (typically `/home/elestio`)
5. Click **Upload File** and select your local `keys.env` file
6. Once uploaded, note the path for reference

### 2.4 Set Secrets in Supabase Edge Functions

Supabase on Elestio also allows you to set secrets directly in the dashboard. To do this:

1. In the **Supabase Dashboard**, navigate to **Edge Functions** > **Manage Secrets**
2. For each variable in your `keys.env` file:
   - Click **Add New Secret**
   - Enter the **Name** (e.g., `SUPABASE_URL`)
   - Enter the **Value** (the corresponding value from your `keys.env`)
   - Click **Save**

> **Alternative:** If you prefer CLI access, SSH into your Elestio instance and use `supabase secrets set VARIABLE_NAME=value` directly.

---

## Step 3: Import Database Schema

### 3.1 Access SQL Editor from Supabase Dashboard

1. In the **Supabase Dashboard** (accessible via Elestio):
   - Click **SQL Editor** in the left sidebar

### 3.2 Retrieve and Import Schema via File Explorer

1. **Locate the schema file:**
   - In your Elestio instance, use the **File Manager** to navigate to:
     ```
     supabase/setup/schema/normsar_silo_schema.sql
     ```

2. **Copy the schema content:**
   - Download or view the file content from Elestio File Explorer
   - Copy the entire SQL script

3. **Paste into SQL Editor:**
   - In the Supabase **SQL Editor**, click **New Query**
   - Paste the entire schema SQL
   - Click **Run**

4. **Wait for completion:**
   - The schema includes AI vector support, governance logic, and all required tables
   - Check the output for confirmation

> **File size note:** The schema is approximately 96 lines of PL/pgSQL. If you encounter timeout issues, you may need to split the import into smaller sections.

---

## Step 4: Deploy Edge Functions

### 4.1 Locate Edge Functions in Repository

Your repository contains several pre-built Edge Functions in:
```
supabase/setup/functions/
```

Available functions include:
- **feed-ai** – Process documents and embeddings for AI
- **send-message** – Route and store chat messages
- **silo-daily-briefing** – Generate AI-powered daily briefings
- **normsar-ai** – Semantic search and RAG integration
- **authenticate-hub-user** – Verify Normsar Hub tickets
- **verify-membership** – Check room membership
- **check-e2ee-status** – Verify E2EE configuration
- **sponsor-lit-action** – Lit Protocol integration

### 4.2 Deploy Functions via Supabase Dashboard

1. In the **Supabase Dashboard**, go to **Edge Functions**
2. Click **Deploy New Function** (via Editor)
3. For each function you want to deploy:
   - **Name:** Use the exact folder name (e.g., `feed-ai`, `send-message`)
   - **Source:** Copy the entire content from `supabase/setup/functions/{function-name}/index.ts`
   - Paste into the editor
   - Click **Deploy**

### 4.3 Deploy Functions via Elestio File Explorer (Alternative)

If using the Supabase CLI (available on Elestio):

1. **SSH into your Elestio instance:**
   ```bash
   ssh elestio@your-elestio-instance.com
   ```

2. **Navigate to your project:**
   ```bash
   cd /path/to/normsar-silo
   ```

3. **Deploy all functions at once:**
   ```bash
   supabase functions deploy
   ```

4. **Or deploy a specific function:**
   ```bash
   supabase functions deploy feed-ai
   ```

### 4.4 Configure JWT Verification

For each deployed Edge Function:

1. In the **Supabase Dashboard**, go to **Edge Functions**
2. Click on the function name
3. Click **Settings**
4. Set **Verify JWT with legacy secret** to **OFF**
5. Save

> **Why OFF?** Silo uses custom JWT verification logic to support both legacy and modern tokens.

---

## Step 5: Retrieve Supabase Credentials for Silo Registration

Before registering your Silo with Normsar, gather your access credentials:

1. **From Supabase Dashboard** (via Elestio):
   - Go to **Project Settings** > **API**
   - Copy your **Project URL** (e.g., `https://your-project-id.supabase.co`)
   - Copy your **Anon Key**

2. **Note your instance:**
   - Your Elestio Supabase instance URL might differ from the standard supabase.co domain if using a custom domain
   - Confirm the correct URL in your Elestio dashboard

---

## Step 6: Register Your Silo with Normsar

1. Go to [https://normsar.io/silo-manager](https://normsar.io/silo-manager)
2. Sign in with your Normsar account
3. Click **Register New Silo**
4. Fill in the registration form:
   - **Silo Name:** A unique name for your node (e.g., `My Elestio Silo`)
   - **Project URL:** Paste your Supabase Project URL from Step 5
   - **Anon Key:** Paste your ANON_KEY from Step 5
5. Click **Register**
6. Your Silo is now linked to the Normsar ecosystem

---

## ✅ Verification

After completing all steps, verify your setup:

### 1. Check Database Tables

1. In the **Supabase Dashboard**, go to **SQL Editor**
2. Run the following query:
   ```sql
   SELECT * FROM public.profiles LIMIT 5;
   ```
3. You should see the **Normsar AI** system profile with ID: `00000000-0000-0000-0000-000000000000`

### 2. Test Edge Functions

1. In the **Supabase Dashboard**, go to **Edge Functions**
2. Select a function and click **Invoke**
3. Verify that the function responds (even if with a test error, it confirms deployment)

### 3. Monitor Logs

1. In the **Supabase Dashboard**:
   - Go to **Edge Functions** > **Logs**
   - Monitor function execution for errors or issues

2. In **Elestio File Manager**:
   - Check application logs at `/var/log/supabase/` or similar
   - Refer to Elestio documentation for exact log locations

---

## Troubleshooting

### Issue: "Missing secrets" error in Edge Functions

**Solution:**
1. Verify all secrets are set in **Edge Functions > Manage Secrets**
2. Ensure secret names match exactly (case-sensitive)
3. Redeploy the affected Edge Function after updating secrets

### Issue: SQL schema import fails

**Solution:**
1. Check for syntax errors in the SQL Editor output
2. Ensure the database user has necessary permissions
3. Try importing in smaller chunks (split by table)

### Issue: Edge Functions timeout

**Solution:**
1. Check Elestio instance resource allocation (CPU/Memory)
2. Verify network connectivity to external APIs (Gemini, Lit Protocol)
3. Review function logs for long-running operations

### Issue: Cannot access Supabase Dashboard from Elestio

**Solution:**
1. Ensure your Elestio service is running
2. Check your firewall/security group rules
3. Verify your IP is whitelisted on Elestio

---

## Next Steps

1. **Deploy your client application** – Connect to your Silo using the Project URL and ANON_KEY
2. **Enable AI features** – Configure GEMINI_API_KEY for AI briefings and search
3. **Set up E2EE** – Configure LIT_PKP_PUBLIC_KEY and LIT_API_KEY for encryption
4. **Monitor performance** – Use Elestio monitoring tools to track database and function usage

---

## Support

For Elestio-specific issues:
- [Elestio Documentation](https://elestio.com/docs)
- Elestio Support: support@elestio.com

For Normsar Silo issues:
- [Normsar Documentation](https://normsar.io/docs)
- Repository: [sengtha/Normsar-Silo](https://github.com/sengtha/Normsar-Silo)
