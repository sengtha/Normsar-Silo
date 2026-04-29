# 🗄️ Setting Up Your Personal Vault (Cloudflare R2)

Welcome to your **Personal Vault**! By default, the Normsar Hub allows you to send text messages and optimized photos. However, to unlock the full power of sovereign messaging—including unrestricted file sharing, high-res photos, and voice chats—you can connect your own cloud storage. 

We utilize **Cloudflare R2** because it offers a generous free tier (10 GB of free storage per month) and perfectly aligns with our vision of you owning your data. 

Follow the steps below to configure your R2 bucket and fill out the form in your Normsar Profile.

---

### Step 1: Create a Cloudflare Account
If you don't have one already, you need to create a free Cloudflare account.
1. Go to [dash.cloudflare.com/sign-up](https://dash.cloudflare.com/sign-up) and register.
2. Verify your email address.
3. Once logged in, navigate to **R2** in the left-hand sidebar. You may need to add a payment method to activate R2, but you won't be charged unless you exceed the free tier.

### Step 2: Get Your Cloudflare Account ID
1. Look at the URL in your browser while logged into the Cloudflare dashboard. 
2. It will look something like this: `dash.cloudflare.com/1234567890abcdef1234567890abcdef/r2`
3. That long string of numbers and letters after `dash.cloudflare.com/` is your Account ID.
4. **Copy this and paste it into the `Cloudflare Account ID` field in Normsar.**

### Step 3: Create Your Bucket
1. In the R2 dashboard, click the **Create bucket** button.
2. Give your bucket a unique name (e.g., `my-normsar-vault`).
3. Click **Create bucket**.
4. **Copy your exact bucket name and paste it into the `Bucket Name` field in Normsar.**

### Step 4: Set Up the Public Domain
To allow Normsar to display your uploaded files and voice notes, you need to enable public access.
1. Inside your newly created bucket, go to the **Settings** tab.
2. Scroll down to the **Public Access** section.
3. Under **Custom Domains**, click **Connect Domain** (if you have your own domain on Cloudflare) OR enable the **R2.dev subdomain**.
4. Once enabled, Cloudflare will generate a public URL for you (e.g., `https://pub-xyz.r2.dev`).
5. **Copy this URL and paste it into the `Public Custom Domain` field in Normsar.**

### Step 5: Apply the CORS Policy
This is a crucial step! CORS (Cross-Origin Resource Sharing) tells Cloudflare that it is safe to accept files uploaded directly from the Normsar app.
1. Still in your bucket's **Settings** tab, scroll down to the **CORS Policy** section.
2. Click **Add CORS policy**.
3. Switch to the **JSON** editor and paste the following exact code:

```json
[
  {
    "AllowedOrigins": [
      "[https://normsar.io](https://normsar.io)"
    ],
    "AllowedMethods": [
      "PUT",
      "GET"
    ],
    "AllowedHeaders": [
      "Content-Type"
    ],
    "ExposeHeaders": [
      "ETag"
    ],
    "MaxAgeSeconds": 3000
  }
]
````
4. Click **Save**.
                                       
### Step 6: Generate Your Access Keys
Finally, you need the secure "keys" that allow your Normsar profile to read and write to this bucket.
1. Go back to the main **R2** dashboard page (click R2 in the left sidebar).
2. On the right side of the screen, click **Manage R2 API Tokens**.
3. Click **Create API token**.
4. Set the permissions to **Object Read & Write**.
5. Specify your specific bucket (the one you just created) under the "Specify bucket(s)" section for maximum security.
6. Click **Create API Token**.
7. You will be shown two secret keys. **Copy the Access Key ID and paste it into Normsar**.
8. **Copy the Secret Access Key and paste it into Normsar**. (Note: You will only see this secret key once, so copy it immediately!)

### 🎉 All Done!
Once you have filled in all five fields in the Normsar app, click **Save**. You are now fully equipped with a secure, personal data vault, unlocking unrestricted media and voice features across the platform!
