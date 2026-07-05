# 🔗 STAR Kidz Dashboard — Busy ERP Integration Guide

## **STEP 1: Get Your Busy API Credentials**

### **Option A: Busy Cloud Portal**
1. Log in to your Busy account at **https://www.busyworks.in/**
2. Navigate to **Settings → API Keys** (or **Settings → Developer Settings**)
3. Look for:
   - **Organization ID** (usually a numeric ID like 12345)
   - **API Key** (a long alphanumeric string)
4. Copy both values

### **Option B: Contact Busy Support**
If you don't see API settings in your dashboard:
- Email: **support@busyworks.in**
- Phone: **+91 1133-330-022**
- Request: "API Key for organization [Your Org Name]"
- They'll provide Organization ID & API Key within 24 hours

---

## **STEP 2: Configure Dashboard Integration**

1. Open **STAR Kidz Sales Dashboard**
2. Click **🔗 Link & Configure** button (top right)
3. In the modal, find **🔗 Busy ERP Integration** section
4. Enter:
   - **Busy Organization ID**: `[Your numeric ID]`
   - **Busy API Key**: `[Your API key]`
5. Click **🔗 Connect Busy ERP** button
6. You should see: ✅ Connected at [time]

---

## **STEP 3: Sync Your Data**

### **First-Time Sync**
1. After connecting, click **↻ Sync Now** button
2. Wait for sync to complete (usually 30-60 seconds)
3. You'll see:
   - ✅ Last synced: [timestamp]
   - 📦 Inventory: [X] articles
   - 🏭 Pipeline: [Y] articles

### **What Gets Synced**

| Data | From Busy | Synced To |
|------|-----------|-----------|
| **Finished Goods Stock** | Inventory Module | IV — 📦 Inventory Tab |
| **Article Master** | Item Master | Article-wise & Series-wise tables |
| **Sales Orders** | Sales Module | II — Pull Sale & Dashboard |
| **Party Data** | Party Master | Customer database |
| **Production Data** | Production Module | V — 🏭 Production Pipeline |
| **Stock Quantity** | Inventory Closing | Stock (ctns) & Stock (pairs) |

---

## **STEP 4: Automatic Sync Schedule** (Coming Soon)

Once connected, the dashboard will:
- ✅ Auto-sync every **4 hours** (configurable)
- ✅ Pull latest inventory from Busy
- ✅ Update pipeline progress
- ✅ Refresh sales data
- ✅ Keep all data fresh without manual action

---

## **TROUBLESHOOTING**

### **❌ "Not connected" message**
**Solution:**
1. Check that you entered **exact** Organization ID and API Key
2. Verify API Key is active in Busy (not revoked)
3. Re-enter credentials and click Connect again

### **❌ Sync fails after 30 seconds**
**Possible causes:**
1. **Network issue**: Check internet connection
2. **API Key expired**: Get new key from Busy
3. **Firewall blocking**: Contact IT to whitelist `secure.busyworks.in`

**Solution:**
- Try sync again
- If persistent, contact Busy support

### **❌ "Articles not showing in inventory"**
**Check:**
1. Are articles in Busy marked as **"Active"**?
2. Is stock quantity **> 0**?
3. Did sync complete successfully?

**Solution:**
- Click **↻ Sync Now** again
- Check Busy inventory module to ensure articles exist

---

## **API ENDPOINTS SYNCED**

The dashboard connects to these Busy API endpoints:

```
📦 Inventory Stock
GET /api/v1/inventory/stock?organizationId={orgId}

💼 Sales Data  
GET /api/v1/sales?organizationId={orgId}

👥 Party Master (Customers)
GET /api/v1/parties?organizationId={orgId}

🏭 Production Data
GET /api/v1/production?organizationId={orgId}
```

All requests include:
- **Authorization Header**: `Bearer [Your API Key]`
- **Content-Type**: `application/json`

---

## **DATA REFRESH FREQUENCY**

| Module | Refresh Rate | Manual Sync |
|--------|-------------|-----------|
| Finished Goods | Every 4 hours | ↻ Sync Now (anytime) |
| Sales Orders | Every 4 hours | ↻ Sync Now (anytime) |
| Pipeline Progress | Every 4 hours | ↻ Sync Now (anytime) |
| Party Master | Daily | Manual import |

---

## **QUICK REFERENCE**

| Action | Where | How |
|--------|-------|-----|
| **Connect Busy** | Link & Configure → Busy ERP | Enter credentials → Click Connect |
| **Sync Now** | Link & Configure → Busy ERP | Click ↻ Sync Now |
| **Check Sync Status** | Link & Configure → Busy ERP | Look at "Last synced" timestamp |
| **View Finished Goods** | I — Push Sale (bottom) | See raw article stock data |
| **View Inventory** | IV — 📦 Inventory | See all articles + filters |
| **View Production** | V — 🏭 Production Pipeline | See production progress |

---

## **SUPPORT**

**For Dashboard Issues:**
- Contact: **Bd.executive@starkidz.co.in**
- Dashboard support available during business hours

**For Busy API Issues:**
- Contact: **support@busyworks.in**
- Website: **https://www.busyworks.in/**
- Phone: **+91 1133-330-022**

---

## **SECURITY NOTES**

⚠️ **IMPORTANT:**
- ✅ API Key is stored **locally** (in your browser)
- ✅ Never share your API Key with anyone
- ✅ API Key is **encrypted** when stored
- ✅ Data is synced over **HTTPS** (secure connection)
- ✅ Clear browser cache if switching devices

---

**Last Updated:** July 5, 2026
**Dashboard Version:** 1.2.0
