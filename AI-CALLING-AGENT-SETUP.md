# 🤖 STAR Kidz AI Calling Agent — Setup Guide

**Architecture:** Claude API (brain) · Vapi.ai (voice) · Make.com or n8n (glue) · Firebase (database)
**Date:** July 6, 2026

---

## ⚠️ One correction to the plan

`claude-3-5-sonnet` is an **outdated model**. Use the current API models:

| Use | Model ID |
|-----|----------|
| Call analysis, intent & sentiment (recommended) | `claude-sonnet-5` |
| Cheapest / high volume (transcript triage) | `claude-haiku-4-5-20251001` |

Everything else in the architecture stands.

## ⚠️ You already have n8n — decide before building Make.com

The dashboard's AI Agent page already has **two n8n workflows** in this folder:
- `n8n-starkidz-leadgen.json` (approved mails/calls outreach)
- `n8n-starkidz-discovery.json` (fresh-lead discovery)

n8n and Make.com do the same job. **Pick one** — if the n8n instance is already running, extend it instead of paying the Make.com learning curve twice. The stage flow below works identically in either tool.

---

## 1. Files delivered

| File | Purpose |
|------|---------|
| `firebase-crm-structure.json` | Import into Firebase Realtime Database (**Database → ⋮ → Import JSON**). Creates `config`, `leads`, `call_log`, `daily_queue` collections with all 9 stages defined. |
| `firebase-leads-import.csv` | Same lead schema flat — use for the Google Sheets / AppSheet / Glide alternative instead of Firebase. |

Delete `LEAD-0001` / `CALL-0001` sample rows after your first real import.

## 2. The 9 stages → where they live

| Stage | What happens | Field driving it |
|-------|--------------|------------------|
| 1 Sourcing | Apify scrapes IndiaMART/JustDial "footwear distributors" | `source` |
| 2 Capture | Webhook saves scraped lead | `stage: 2`, `status: New` |
| 3 Selection | Morning job qualifies leads | `status: ReadyToCall` |
| 4 Catalogue | WhatsApp auto-send on interest | `catalogue_sent`, `config.whatsapp.*` |
| 5 CRM | Everything synced to dashboard | whole `leads` collection |
| 6 WhatsApp/Email | Status-change → approved template | `status` transitions |
| 7 AI Calling | Vapi.ai dials ReadyToCall leads | `call_attempts`, `next_call_at` |
| 8 Re-sourcing | Weekly refresh of stale pools | `updated_at` age |
| 9 Conversion | Outcome tagging | `conversion_tag` 1/2/3 |

## 3. Backend logic (corrected blueprint)

```python
import anthropic

client = anthropic.Anthropic()  # ANTHROPIC_API_KEY from env

def handle_call_transcript(lead_id: str, transcript: str) -> dict:
    msg = client.messages.create(
        model="claude-sonnet-5",
        max_tokens=500,
        messages=[{
            "role": "user",
            "content": (
                "You are the call analyst for STAR Kidz (kids & ladies footwear). "
                "Analyze this sales call transcript and reply ONLY with JSON: "
                '{"interested": bool, "transfer_to_human": bool, '
                '"conversion_tag": 0|1|2|3, "summary": "one line"}\n\n'
                f"Transcript:\n{transcript}"
            ),
        }],
    )
    result = json.loads(msg.content[0].text)

    if result["transfer_to_human"]:
        action = {"action": "TRANSFER", "phone": "+919253083246"}
    elif result["interested"]:
        action = {"action": "SEND_CATALOGUE", "channel": "WHATSAPP"}
    else:
        action = {"action": "LOG_ONLY"}

    db.reference(f"leads/{lead_id}").update({
        "status": "Contacted",
        "conversion_tag": result["conversion_tag"],
        "narration": result["summary"],
        "updated_at": datetime.now(IST).isoformat(),
    })
    return action
```

Key differences from the draft: current model id, JSON-forced output (no fragile `response.contains(...)` string matching), and the conversion tag written in the same pass.

## 4. Hard rules already configured in `config`

- **Approval-gated**: `approval_required_for_mail/call: true` — nothing goes out without a human clicking approve (matches the dashboard agent page).
- **Calling window**: Mon–Sat, 10:00–19:30 IST, Sunday off.
- **Interested calls forward to** +91 92530 83246.
- **Busy dedup**: `busy_party_check` must be `clean` before any outreach — set it by checking against the exported Busy party list.

## 5. Catalogue & brand-profile links (✅ DONE — hosted on Vercel)

The PDFs are hosted on your own Vercel site and already wired into `config.whatsapp`:

| Asset | Public URL |
|-------|-----------|
| Combined catalogue (main WhatsApp send) | https://starkidz-tracker.vercel.app/catalogues/star-kidz-combined-catalogue.pdf |
| Company / brand profile | https://starkidz-tracker.vercel.app/catalogues/star-kidz-company-profile.pdf |
| Summer — Sandals | https://starkidz-tracker.vercel.app/catalogues/star-kidz-summer-sandals.pdf |
| Winter — Shoes | https://starkidz-tracker.vercel.app/catalogues/star-kidz-winter-shoes.pdf |
| Star Ride — Ladies | https://starkidz-tracker.vercel.app/catalogues/star-ride-ladies-catalogue.pdf |

To update a catalogue later: replace the file in the `catalogues/` folder, commit, push — the URL stays the same.

## 6. Build order

1. Create Firebase project → Realtime Database → **Import** `firebase-crm-structure.json`
2. Vapi.ai account → create assistant → set server webhook to your Make.com/n8n scenario
3. Make.com/n8n: scenario A (webhook → save lead), scenario B (status=Interested → WhatsApp catalogue), scenario C (Vapi end-of-call → `handle_call_transcript`)
4. Paste catalogue/brand links into config
5. Test with your own number as LEAD-0001 before going live
