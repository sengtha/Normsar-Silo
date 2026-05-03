# 🛡️ Guide: Setting up Lit Protocol for NORMSAR E2EE

To enable true End-to-End Encryption (E2EE) for chat rooms within your NORMSAR Silo, you need to configure a decentralized encryption key manager using Lit Protocol. 

Follow these steps to generate the required credentials and link them to your Silo's Edge Functions.

### Step 1: Create a Lit Express Account
1. Visit the Lit Express Dashboard: [https://dashboard.chipotle.litprotocol.com/](https://dashboard.chipotle.litprotocol.com/)
2. Sign in or create a new account to manage your Lit Node.

### Step 2: Generate the Usage API Key
This key allows your Silo's Edge Function to communicate with the Lit Network.
1. On your Lit Dashboard, navigate to the **Usage API Keys** section.
2. Click the **Add** button.
3. Give it a recognizable name (e.g., "Normsar E2EE").
4. **Action Required:** Copy the generated API string. You will need to set this as the `LIT_API_KEY` environment secret in your Supabase Edge Function settings.

### Step 3: Provision the PKP (Programmable Key Pair) Wallet
This decentralized wallet acts as the "Master Locksmith" for your Silo's encrypted rooms.
1. On your Lit Dashboard, navigate to the **Wallets** section.
2. Click the **Add** button to create a new wallet.
3. **Action Required:** Copy the generated wallet address (e.g., `0x17a7...`). You will need to set this as the `LIT_PKP_PUBLIC_KEY` environment secret in your Supabase Edge Function settings.

### Step 4: Finalize E2EE Activation
Once both `LIT_API_KEY` and `LIT_PKP_PUBLIC_KEY` are securely saved in your Silo's environment secrets, your setup is complete. 

Your users can now toggle the **E2EE Status** switch when creating new private topics, and the Lit Network will seamlessly manage the encryption keys in the background!
