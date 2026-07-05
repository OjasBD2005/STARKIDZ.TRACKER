# 📥 CSV Import Guide — Real Inventory Data

## Overview
The dashboard now supports direct CSV import from your Busy/Inventify exports. Replace sample data with your real inventory data in 2 minutes.

---

## ✅ Features

### What Gets Imported
- ✅ Article codes (extracted from SKU prefix)
- ✅ Stock quantities (aggregated by article)
- ✅ Converts individual pairs to cartons (12 pairs/carton)
- ✅ Updates Inventory (IV) tab automatically
- ✅ Updates Finished Goods Stock (in Push Sale)
- ✅ Stores in localStorage for offline access

### CSV Format Expected
```
DropshipWarehouseId,Item SkuCode,InventoryAction,QtyIncludesBlocked,Qty,RackSpace,Last Purchase Price,Notes,Bad Stock
29867,SKZASH02-BBYPNK-16,RESET,No,144,,,Backlog,0
29867,SKZASH02-BBYPNK-17,RESET,No,72,,,Current,0
29867,SKZBEAR13-KHK-1,RESET,No,6,,,Stock,0
```

**Required columns:**
- Column 1: Item SkuCode (e.g., `SKZASH02-BBYPNK-16`)
- Column 4: Qty (quantity in pairs)

**How it works:**
- Extracts article code from SKU: `SKZASH02-*` → `SKZASH02`
- Aggregates all SKU sizes/colors by article code
- Converts pairs to cartons: `144 pairs ÷ 12 = 12 ctns, 0 pairs`

---

## 🚀 Quick Start

### Step 1: Prepare Your CSV File
Export your inventory from Busy:
1. **Busy Portal** → Inventory Module
2. Click **Export to CSV** or **Download Stock Report**
3. Save as `skz inventory.csv` or similar
4. File should contain SKU codes and quantities

### Step 2: Open Dashboard
1. Go to your dashboard: [starkidz-tracker.vercel.app/...](https://starkidz-tracker.vercel.app/star-kidz-sales-dashboard.html)
2. Click **🔗 Link & Configure** (top-right button)
3. Scroll to **📊 Import Exported Data** section (left side)

### Step 3: Upload CSV
1. Click **Choose File** button
2. Select your `skz inventory.csv` file
3. Click **📥 Import Inventory Data** button
4. ✅ See status: "Imported X articles from CSV"

### Step 4: Verify Data
1. Click **IV — 📦 Inventory** tab
2. Scroll through articles table
3. Check **Series-wise** aggregation
4. View **Low Stock** alerts (≤10 ctns)

---

## 📊 Example: How Data Transforms

### Input CSV
```
SKZASH02-BBYPNK-16,RESET,No,144
SKZASH02-BBYPNK-17,RESET,No,72
SKZASH02-MNT-16,RESET,No,84
SKZBEAR13-KHK-1,RESET,No,6
```

### Output (Dashboard)
```
Article: SKZASH02
├─ Stock (ctns): 22
├─ Stock (pairs): 12
└─ Series: SKZASH02

Article: SKZBEAR13
├─ Stock (ctns): 0
├─ Stock (pairs): 6
└─ Series: SKZBEAR13
```

**Calculation:**
- SKZASH02: (144 + 72 + 84) ÷ 12 = 25 ctns, 0 pairs
- SKZBEAR13: (6) ÷ 12 = 0 ctns, 6 pairs

---

## 🔄 Updating Data Regularly

### Weekly/Monthly Updates
1. Export latest CSV from Busy
2. Open dashboard → Link & Configure
3. Upload new CSV file
4. ✅ Previous data replaced with new data
5. All views (Inventory, Push Sale) auto-refresh

### Clear Cache (if needed)
Browser DevTools → Application → localStorage
- Delete: `starkidz_inventory`
- Refresh page to reload default sample data

---

## 📝 Notes

### Data Limitations
- ❌ Currently no category/machine data in CSV import
  - These can be added manually in Busy after import
- ❌ Series is auto-populated with article code
  - Edit in Inventory tab if different
- ⚠️ Assumes 12 pairs per carton
  - Adjust in code if different

### File Size
- ✅ Supports CSV files up to browser limit (~100MB)
- ✅ Typical Busy export: 50KB - 1MB
- Faster imports with smaller files

---

## 🐛 Troubleshooting

### "CSV is empty"
→ File might be malformed or have no data rows
→ Verify CSV has header + at least 1 data row

### "Error parsing CSV"
→ Check CSV format matches expected columns
→ Ensure column 1 = SKU, column 4 = Qty (numbers only)

### No articles imported
→ SKU format must have hyphen: `SKZASH02-BBYPNK-16`
→ Check that Qty values are numeric (not text)

### Wrong quantities
→ Verify carton size (default = 12 pairs)
→ Check Qty column is in pairs, not units

---

## 📥 Files to Download

**From Busy (for use with this import):**
- Downloads/skz inventory.csv
- Downloads/Stock-4-7-2026.xlsx (manual import alternative)
- Downloads/Selected Period Sales.xlsx (for sales tab)

---

## 🎯 Next Steps

✅ **Try it now:**
1. Download your latest Busy inventory CSV
2. Open dashboard → Link & Configure → Choose File
3. Import and see data in Inventory tab

✅ **Then connect Busy API:**
1. Get credentials from Busy support
2. Paste into Busy ERP Integration section
3. Click "Connect Busy ERP" + "Sync Now"
4. Auto-sync every 4 hours thereafter

---

**Questions?**
- Dashboard: Bd.executive@starkidz.co.in
- Busy Support: support@busyworks.in

---

**Last Updated:** July 5, 2026  
**Version:** 1.3.0 (CSV Import Added)
