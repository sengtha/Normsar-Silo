# Normsar-Silo
The self-hosted, decentralized data node for Normsar Sovereign Messaging. Deploy your own Silo to achieve true data sovereignty and connect securely to the Normsar Hub.

# 🚀 Silo Setup Guide

Follow these steps to deploy and register your own sovereign messaging node.

---

### 1. Configure Edge Function Secrets
You must set a JWT secret to secure communication between your Silo and the Normsar network.
1. Go to your **Supabase Dashboard**.
2. Navigate to **Project Settings** -> **API**.
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

### 4. Register your Silo
Link your infrastructure to the Normsar ecosystem.
1. Go to [https://normsar.io/silo-manager](https://normsar.io/silo-manager) (Sign-in required).
2. Obtain your **Project URL** and **Anon Key** from **Project Settings** -> **API** in your Supabase Dashboard.
3. Input these credentials into the registration form.
4. Click **Register** to finalize your sovereign node.
