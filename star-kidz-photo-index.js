/* STAR Kidz - per-article / per-colour photo index.
   The article name, colour, sizes and MRP are printed INSIDE each catalogue photo
   (e.g. "Creta-03 / OLV / 4X7 I 5X8 I 6X9 / MRP 549.99"), and the file names do not
   carry them - so each entry below was read off the image itself.
   Keys: "ARTICLE|COLOUR" for an exact match, "ARTICLE" as a per-article fallback.
   The catalogue falls back to the series photo when an article isn't listed here.
   Extend: add rows to tools/stock-catalogue/photo_index.csv and rerun build_photo_index.ps1 */
window.PHOTO_INDEX = {"CRETA-3|OLV":"CRETA-3__OLV.jpg","CRETA-3":"CRETA-3__OLV.jpg","DIYA-02|KHK":"DIYA-02__KHK.jpg","DIYA-02":"DIYA-02__KHK.jpg","SPORTS-54|PPL":"SPORTS-54__PPL.jpg","SPORTS-54":"SPORTS-54__PPL.jpg","ITALY-06|NBL":"ITALY-06__NBL.jpg","ITALY-06":"ITALY-06__NBL.jpg"};
