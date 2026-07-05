# 🔐 How to Get Your Busy API Credentials

## **METHOD 1: Through Busy Web Portal (RECOMMENDED)**

### **Step 1: Login to Busy**
1. Open: **https://www.busyworks.in/**
2. Enter your credentials (Username & Password)
3. Click **Login**

### **Step 2: Navigate to Settings**
1. Click your **Profile Icon** (top-right corner)
2. Select **Settings** (or **Company Settings**)
3. Look for menu items like:
   - Settings
   - Developer
   - API
   - Integrations

### **Step 3: Find API Section**
In Settings, look for:
- **API Keys**
- **Developer Settings**
- **Integrations**
- **Developer Portal**

If you don't see it:
- Check under **Advanced Settings**
- Check under **Tools & Utilities**
- Contact support (see METHOD 2)

### **Step 4: Generate/Copy Credentials**
In the API section, you should see:

**Organization ID**
- Format: `12345` (numeric)
- Also called: Org ID, Company ID, Organization Code
- Copy and save this

**API Key**
- Format: `abc123def456ghi789...` (long alphanumeric)
- Also called: API Token, Secret Key, Access Key
- ⚠️ **KEEP THIS PRIVATE** - Never share!
- Copy and save this

### **Step 5: If No API Section Found**
Click on **Generate API Key** or **Create New Key** button if available

---

## **METHOD 2: Contact Busy Support**

If you can't find the API section in your dashboard:

### **Email Support**
```
To: support@busyworks.in
Subject: Request API Key for Organization

Message:
Hi,
I need an API key for my Busy account to integrate with our sales dashboard.

Details:
- Organization Name: [Your Company Name]
- Username: [Your Busy login username]
- Email: [Your email]

Please provide:
1. Organization ID
2. API Key

Thank you!
```

### **Phone Support**
- **Number**: +91 1133-330-022
- **Timing**: Business hours (9 AM - 6 PM IST)
- **Say**: "I need API credentials for integrating my sales dashboard with Busy"

### **Live Chat (if available)**
- Visit: https://www.busyworks.in/
- Look for **Chat** or **Support** icon
- Ask for API credentials

### **Response Time**
- Email: 24-48 hours
- Phone: Immediate
- Live Chat: 1-2 hours

---

## **ALTERNATIVE: Generate Within Your Busy Account**

### **If Busy has Self-Service API Generation:**

1. **Settings → Developer → API Keys**
2. Click **Generate New Key** or **Create API Key**
3. Give it a name: `STAR_Kidz_Dashboard`
4. Set permissions:
   - ✅ Inventory Read
   - ✅ Sales Read
   - ✅ Party Read
   - ✅ Production Read (if applicable)
5. Click **Generate**
6. **IMPORTANT**: Copy the key immediately (shown only once!)
7. Save Organization ID from same page

---

## **WHAT YOU'LL GET**

After completing above steps, you'll have:

### **Example Credentials:**
```
Organization ID: 54321
API Key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### **Keep These Safe:**
- 📄 Copy to a text file
- 🔒 Save in secure location (not email or chat)
- 🚫 Don't share with anyone
- ✅ Backup copy recommended

---

## **STEP 6: Enter in Dashboard**

Once you have both credentials:

### **In STAR Kidz Dashboard:**
1. Click **🔗 Link & Configure** (top-right)
2. Scroll to **🔗 Busy ERP Integration** section
3. Paste:
   - **Organization ID**: `54321`
   - **API Key**: `eyJhbGciOi...` (paste the full key)
4. Click **🔗 Connect Busy ERP**
5. You should see: ✅ Connected at [time]
6. Click **↻ Sync Now** to import your data

---

## **TROUBLESHOOTING**

### **"Invalid Credentials"**
- ❌ Organization ID wrong
- ❌ API Key wrong
- ❌ API Key revoked/expired in Busy

**Fix:**
1. Double-check copied credentials
2. Ask Busy support for new credentials
3. Make sure key hasn't expired (check Busy dashboard)

### **"API Key Expired"**
**Fix:**
1. Go back to Busy API settings
2. Generate a new API Key
3. Update in dashboard
4. Try sync again

### **"Connection Timeout"**
- ⚠️ Network issue
- ⚠️ Busy servers down
- ⚠️ Firewall blocking

**Fix:**
1. Check internet connection
2. Try again after 5 minutes
3. Contact your IT if firewall blocks: `secure.busyworks.in`

### **"No Data After Sync"**
- Articles might not be marked "Active" in Busy
- Stock quantity might be zero

**Fix:**
1. Check Busy Inventory module
2. Ensure articles are Active
3. Ensure stock qty > 0
4. Try sync again

---

## **SECURITY BEST PRACTICES**

✅ **DO:**
- Keep API Key private
- Use strong password for Busy
- Store credentials securely
- Enable 2-factor authentication in Busy

❌ **DON'T:**
- Share API Key in emails or messages
- Commit API Key to code
- Use weak passwords
- Leave API Key visible on screen

---

## **CREDENTIAL LOCATION AFTER GETTING THEM**

Once you have your credentials, store them as:

### **Option 1: Password Manager**
- LastPass
- 1Password
- Bitwarden
- Microsoft Edge's built-in password manager

### **Option 2: Secure Document**
- Encrypted Word doc
- Password-protected Excel
- Secure note-taking app

### **Option 3: Keep in Memory**
- Memorize Organization ID
- Keep API Key in password manager only
- Never write in plain text

### **DO NOT:**
- ❌ Email to yourself
- ❌ Store in shared drives
- ❌ Write in notebook
- ❌ Share in Slack/Teams

---

## **QUICK REFERENCE**

| Need | Where to Find |
|------|---------------|
| **Organization ID** | Busy Dashboard → Settings → API Section |
| **API Key** | Busy Dashboard → Settings → Developer → API Keys |
| **Support** | support@busyworks.in or +91 1133-330-022 |
| **API Status** | https://status.busyworks.in/ |

---

## **WHAT PERMISSIONS DO I NEED?**

Usually, your current Busy user needs:
- ✅ **Read access** to Inventory
- ✅ **Read access** to Sales
- ✅ **Read access** to Parties
- ✅ **Read access** to Production (optional)

You likely already have these if you use Busy daily.

---

## **CAN I REVOKE THE API KEY LATER?**

**Yes!** Anytime you want to disconnect:

1. Go to Busy API settings
2. Find the API Key (named `STAR_Kidz_Dashboard`)
3. Click **Delete** or **Revoke**
4. Dashboard won't be able to access Busy anymore
5. (Optional: Generate a new key to re-connect)

---

## **ESTIMATED TIME**

⏱️ **Total Time to Get Credentials:**

- **Self-service (Busy web portal):** 5-10 minutes
- **Email support:** 24-48 hours
- **Phone support:** 30 minutes (including call time)
- **Dashboard setup:** 2 minutes

---

**Questions?**
- 📧 Email support@busyworks.in
- 📞 Call +91 1133-330-022
- 💬 Live chat at busyworks.in

---

**Last Updated:** July 5, 2026
