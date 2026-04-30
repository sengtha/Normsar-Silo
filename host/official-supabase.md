# 🚀 Normsar Silo Setup Guide (Official Supabase)

Follow these steps to deploy and register your own sovereign messaging node using the official Supabase platform. You can start entirely on their Free tier.

---

### 1. Sign up and Create a Supabase Project
Before configuring your Silo, you need to create your database infrastructure.
1. Go to [supabase.com](https://supabase.com) and click **Start your project**.
2. Sign up using your GitHub account or email address.
3. Once logged into the dashboard, click **New Project**. (You may be prompted to create a new Organization first—give it any name you prefer).
4. Fill in your project details:
   - **Name:** Choose a name for your node (e.g., `My Normsar Silo`).
   - **Database Password:** Generate a secure password and save it somewhere safe.
   - **Region:** Select the server region geographically closest to you for the best performance.
   - **Pricing Plan:** Ensure the **Free** tier is selected.
5. Click **Create new project**. It will take a few minutes for your database to provision and come online.

### 2. Configure Edge Function Secrets
You must set a JWT secret to secure communication between your Silo and the Normsar network.
1. Go to your **Supabase Dashboard**.
2. Navigate to **Project Settings** -> **API**.
3. Under the **JWT Settings** section, copy the **JWT Secret** (Legacy JWT secret).
4. Go to **Edge Functions** -> **Manage Secrets** in the sidebar.
5. Click **Add New Secret**:
   - **Name:** `SILO_JWT_SECRET`
   - **Value:** Paste the JWT secret you copied in step 3.

### 3. Import Database Schema
Apply the core architecture, including AI vector support and governance logic.
1. Open the **SQL Editor** from the Supabase Dashboard menu.
2. Open the file: `supabase/setup/schema/normsar_silo_schema.sql` from the repository.
3. Copy the entire content of that SQL file.
4. Paste it into the Supabase SQL Editor and click **Run**.

### 4. Deploy Edge Functions
Deploy the logic required for AI processing and system automation.
1. Navigate to **Edge Functions** in your Supabase Dashboard.
2. Click **Deploy New Function** (Via Editor).
3. Create a function using the exact name found in the `supabase/setup/functions` folder.
4. Copy the code from the corresponding `index.ts` file and save it in the dashboard editor.

### 5. Register your Silo
Link your infrastructure to the Normsar ecosystem.
1. Go to [https://normsar.io/silo-manager](https://normsar.io/silo-manager) (Sign-in required).
2. Obtain your **Project URL** and **Anon Key** from **Project Settings** -> **API** in your Supabase Dashboard.
3. Input these credentials into the registration form.
4. Click **Register** to finalize your sovereign node.

---

### ✅ Verification
After registration, you can verify your setup by checking your `public.profiles` table. You should see the **Normsar AI** system profile (ID: `00000000-0000-0000-0000-000000000000`) automatically inserted.
