# Dispatcher Automation — Build Plan

This doc is the step-by-step build for the Brandon-text → Jobber dispatcher automation. It's the source of truth for what the zap does. When you build it in the Zapier UI, click through these steps in order.

---

## What this does, in one paragraph

Brandon dispatches the day's repair jobs by sending one group text per technician through Quo. Each text contains the customer names + per-customer instructions. Today, after Brandon sends those texts, someone has to manually go into Jobber and (a) assign the tech to each job and (b) for Saturday-parking-lot jobs, move them from Saturday to today's date so the customer notification fires. This automation does both, automatically, the moment Brandon's text arrives. If anything goes wrong (job not found, API error, ambiguous match), it sends Josh an alert email so he can fix it manually before techs head out.

---

## Architecture (run-time data flow)

| # | Step | What it does |
|---|------|--------------|
| 1 | **Trigger** — OpenPhone (Quo) New Message | Fires on every incoming Quo message |
| 2 | **Filter** | Drops message unless sender = Brandon AND a known tech is in the conversation |
| 3 | **Code/Formatter** | Identifies which tech this dispatch is for; sets `target_date = today` |
| 4 | **Jobber: Find Jobs (today, unassigned)** | Pulls all jobs scheduled today with no assignee — the "today-unassigned" candidate pool |
| 5 | **Jobber: Find Jobs (Saturday parking lot)** | Pulls all jobs scheduled this coming Saturday — the "parking lot" candidate pool |
| 6 | **AI Parser** | Given Brandon's text + the two candidate pools, returns structured JSON: `[{client_name, source_bucket, instructions}]` |
| 7 | **Looping action** (per parsed job) | If Saturday → reschedule to today. Assign tech. Add Brandon's instructions as a note on the job. |
| 8 | **Failure handler** | On any per-job failure: append to a list of issues |
| 9 | **Email step** | Send alert email to josh@bluelemonpools.com if any issues occurred (or in v1: send a summary email regardless, for dry-run validation) |

---

## Constants (use these literal values when configuring filters)

| Field | Value |
|---|---|
| Brandon's dispatcher number | **(480) 848-3177** |
| Office line | **(480) 843-0530** |
| Junior — Quo number | **(480) 487-2784** |
| Micah Petersen — Quo number | **(480) 698-4766** |
| Traigen — Quo number | **(480) 265-0943** |
| Chase (training w/ Traigen) — Quo number | **(602) 206-6877** |
| Alert email recipient | **josh@bluelemonpools.com** |
| Tech assignment for Traigen+Chase thread | **Traigen only** (Chase implicit) |

---

## Step-by-step zap configuration

### Step 1 — Trigger: Quo "Incoming Message Received"

- App: **Quo** (the integration is listed under "Quo", not "OpenPhone", post-rebrand)
- Event: **Incoming Message Received**
- Account: the Quo account already connected in Zapier (e.g. josh@bluelemonpools.com)
- Phone Numbers: **Office Main Line — (480) 843-0530**

This trigger is **Instant** (webhook-pushed), not polling, so there's no lag.

**Why Incoming and not Outgoing:** Brandon's number `(480) 848-3177` is his personal cell — NOT a Quo workspace-owned number. The only Quo-owned number is the Office Main Line `(480) 843-0530`. Even though Brandon is a "team member" in the Quo workspace (so his messages get the lemon emoji prefix in display), his SMS is sent from his personal carrier, so from Quo's perspective it's an external incoming message hitting the Office Line.

**Test-trigger gotcha (verified 2026-04-26):** When you click "Test trigger" the panel shows a note "We will load up to 3 most recent records, that have not appeared previously." Because the Quo account is used in many other zaps, recent Josh/Brandon test sends may have already been consumed by one of those zaps and won't show in this zap's Test panel. **Use the Search box at the top of the Test panel** to search for Brandon's number (`4808483177`) and confirm at least one of his historical dispatches appears — that proves the trigger DOES fire on team-member personal-cell sends. If nothing appears even on search, switch to `Outgoing Message Delivered` filtered to Office Main Line as a fallback.

### Step 2 — Filter

Only continue if **all** of these are true:
- `From phone number` **(Text) Exactly matches** `+14808483177`
- One of:
  - `Conversation participants` **Contains** `+14804872784` (Junior)
  - `Conversation participants` **Contains** `+14806984766` (Micah)
  - `Conversation participants` **Contains** `+14802650943` (Traigen)

> **Note**: Phone numbers in Zapier's OpenPhone trigger are E.164 format (`+1...`). Verify on your first test run. If the field is named something other than `Conversation participants` (the OpenPhone trigger sometimes calls it `To phone numbers` or `Conversation contacts`), pick the field that lists ALL participants of the group thread.

### Step 3 — Code by Zapier: identify tech + target date

App: **Code by Zapier** → **Run JavaScript**

```js
const participants = (inputData.participants || "").split(",").map(s => s.trim());

const TECHS = {
  "+14804872784": { name: "Junior",  jobberDisplayName: "Junior Babcock" },
  "+14806984766": { name: "Micah",   jobberDisplayName: "Micah Petersen" },
  "+14802650943": { name: "Traigen", jobberDisplayName: "Traigen Hayrind" },
};

const matched = participants.find(p => TECHS[p]);
if (!matched) {
  throw new Error("Filter passed but no known tech in participants — check filter config");
}

// Arizona is UTC-7 year-round (no DST). Compute today's date in AZ time.
const nowUtc = new Date();
const azOffsetMs = -7 * 60 * 60 * 1000;
const azNow = new Date(nowUtc.getTime() + azOffsetMs);
const targetDate = azNow.toISOString().slice(0, 10); // YYYY-MM-DD

// Compute the next Saturday (today if today is Saturday) in AZ time
const dow = azNow.getUTCDay(); // 0=Sun, 6=Sat
const daysUntilSat = (6 - dow + 7) % 7 || 7;  // always future Sat (never today)
const sat = new Date(azNow.getTime() + daysUntilSat * 86400000);
const saturdayDate = sat.toISOString().slice(0, 10);

output = {
  techName: TECHS[matched].name,
  jobberAssigneeName: TECHS[matched].jobberDisplayName,
  targetDate,
  saturdayDate,
  brandonText: inputData.text,
};
```

**Input data mapping** (set in Code step):
- `participants` ← Trigger > Conversation participants (or equivalent — comma-separated string of E.164 numbers)
- `text` ← Trigger > Message body

### Step 4 — Jobber: Find candidate jobs scheduled for **target_date** with no assignee

This is the "today-unassigned" pool. Use Zapier's native Jobber app actions:
- App: **Jobber**
- Action: **Find Job** (or **Find Jobs by Date** if available — Jobber's Zapier integration has multiple variants)
- Filter: `Start date = {{Step 3 output: targetDate}}`, `Assigned team members is empty` (if filter exists), otherwise return all and filter in Step 6

Output as `today_candidates` (list of `{client_name, job_id, scheduled_date}`).

> **TBD when building**: Confirm the exact field names Jobber's Zapier integration exposes — there may be `Visit start at` vs `Job start at`. Take a screenshot of one Saturday-parking-lot job's detail page in Jobber so we can map the right field names. Drop into this doc when known.

### Step 5 — Jobber: Find candidate jobs scheduled for **saturdayDate**

Same as Step 4 but `Start date = {{Step 3 output: saturdayDate}}`. This is the parking-lot pool.

Output as `saturday_candidates`.

### Step 6 — AI Parser (OpenAI / Claude / Zapier AI)

App: **OpenAI** (or **Claude**, or Zapier's built-in AI step)
Model: GPT-4-class (need accurate name matching, not a small model)
Action: **Send Prompt**

System prompt:

```
You are a strict JSON parser for repair-job dispatch texts. The user is Brandon, a dispatcher at Blue Lemon Pools. He sends a single text to one technician containing instructions for several jobs. Customer names are interleaved with per-customer instructions, with no consistent delimiter and inconsistent casing.

You will be given:
1. Brandon's full dispatch text.
2. Two candidate-customer rosters from Jobber (today-unassigned + Saturday parking lot). Use these as ground truth — any customer named in Brandon's text MUST match one of these.

Your output is JSON only — no prose, no markdown fences. Schema:

{
  "global_notes": "string (any text Brandon wrote that applies to all jobs, e.g. 'Everything is in Gilbert', or empty string)",
  "jobs": [
    {
      "client_name_in_text": "string (exactly as Brandon wrote it)",
      "matched_jobber_client_name": "string (the canonical name from the candidate roster) OR null if no match",
      "source_bucket": "today" | "saturday" | "unmatched",
      "instructions": "string (all of Brandon's per-customer instruction lines, joined with newlines)"
    }
  ]
}

Matching rules:
- The candidate roster entries are JOBS (not just clients). Each entry has a title formatted `{Customer Name} - [optional type prefix like "R"] ({City}) {Job description}`.
- Compare the customer-name portion (the part before " - ") loosely against Brandon's named customer: ignore case, ignore (City) parentheticals, allow common typos (Rapath ↔ Zarapath), allow nicknames (AJ for Apache Junction, etc.).
- **Same-customer-multiple-jobs:** if 2+ candidate jobs share the same customer name (e.g., Janet Moeur has both "Pool Rx, Weekly Service" and "Vacuum Tires/Hose Floats" on the same Saturday), use Brandon's per-customer instruction text to pick the right one — match keywords from the instructions against the job-description portion of the title. If you can confidently pick one, return that job. If not, emit it with `source_bucket: "unmatched"` and a note in the description so the alert system can flag the ambiguity.
- If a name in Brandon's text matches NEITHER roster, set matched to null and source_bucket to "unmatched".
- Do not invent jobs that aren't in Brandon's text.
- Do not skip jobs that are in Brandon's text just because they don't match the roster — emit them with "unmatched" so the alert system catches them.
```

User prompt template:

```
Brandon's text:
---
{{Step 3 output: brandonText}}
---

Today-unassigned candidates ({{Step 3 output: targetDate}}):
{{Step 4 output: today_candidates as bullet list of "Name | job_id"}}

Saturday parking lot candidates ({{Step 3 output: saturdayDate}}):
{{Step 5 output: saturday_candidates as bullet list of "Name | job_id"}}
```

Set output mode to **Structured / JSON**. Parse `jobs` array for the next step.

### Step 7 — Loop: per-job action

App: **Looping by Zapier** → **Create Loop From Line Items**
Iterate over the parsed `jobs` array.

Per iteration:

**7a — Branch on `source_bucket`:**

- **If `unmatched`** → skip to step 7d (queue alert).
- **If `today`** → no date change needed; go to 7b.
- **If `saturday`** → reschedule visit:
  - App: **Jobber**, Action: **Update Visit** (or **Reschedule Visit**)
  - Visit ID: looked up from `job_id` (Jobber's Zapier integration may need an extra "Find Visit by Job" step — check during build)
  - New start date: `{{Step 3: targetDate}}`
  - **The customer notification fires automatically when this date changes** (confirmed by Josh 2026-04-26).

**7b — Assign tech:**
- App: **Jobber**, Action: **Assign Team Member to Job** (or **Update Job → assignedUsers**)
- Job ID: from match
- Team member: `{{Step 3: jobberAssigneeName}}`

**7c — Add note:**
- App: **Jobber**, Action: **Add Note to Job** (or **Add Note to Visit**)
- Note body:
  ```
  Dispatched by Brandon {{zap_run_timestamp}}:
  {{Step 6: global_notes if any}}

  Per-job:
  {{loop.instructions}}
  ```

**7d — On any error in 7a/7b/7c, OR if `unmatched`:**
- Append to a Storage by Zapier list keyed by `zap_run_id`:
  ```
  {client_name_in_text} — {source_bucket} — {error or "no match"} — {instructions}
  ```

### Step 8 — Failure-alert email (only if any issues queued in Step 7d)

App: **Gmail** (or your preferred email sender)
- To: `josh@bluelemonpools.com`
- Subject: `[BLP Dispatch] Manual fix needed — {{Step 3: techName}}, {{Step 3: targetDate}}`
- Body:
  ```
  Heads up — Brandon dispatched {{techName}} for {{targetDate}}. The automation handled what it could, but {{count}} item(s) need your manual attention in Jobber:

  {{list of issues from Storage}}

  ---
  Brandon's original text:
  {{brandonText}}
  ```

### Step 9 (v1 only — dry-run safety rail)

While we're validating, the zap should **not** actually call Jobber's mutation actions. Replace Steps 7a/7b/7c with a single Gmail draft to Josh containing the proposed changes:

> Subject: `[BLP Dispatch DRY-RUN] Proposed changes — {{techName}}, {{targetDate}}`
>
> Body: list of `Move {client} from Saturday to {targetDate}, assign {techName}, add note: {instructions}`

After ~10 dispatches in a row that look correct in the drafts, flip Step 9 off and let Steps 7a/7b/7c run live. Step 8 (alert email) stays on permanently in both modes.

---

## Failure modes that trigger an alert email (final list)

1. **Job not found** — customer name in Brandon's text matches neither today-unassigned nor Saturday parking lot.
2. **Jobber API error** — move-date or assign-tech call returned an error.
3. **Ambiguous match** — parser found 2+ Jobber candidates that both fuzzy-match the same name from Brandon's text.

(Other failure modes like "parser couldn't pick a tech" are structurally impossible — the tech is determined by the message recipient, not the parsed text.)

---

## Open items to resolve during the actual build

- [ ] Confirm Zapier's OpenPhone trigger field name for "all conversation participants" (Step 2 filter).
- [ ] Screenshot of one Saturday-parking-lot job in Jobber so we can pick the right Jobber field names for date filtering (Step 4/5) and rescheduling (Step 7a).
- [ ] Confirm that Jobber's Zapier integration exposes "Update Visit" / "Reschedule Visit" / "Assign Team Member" actions (almost certainly yes, but verify).
- [ ] Verify Brandon's exact display name for Traigen in Jobber — the Jobber team-member name to assign needs to match what Jobber has him as (might be "Traigen Hayrind" or different).
- [ ] First live-fire test should be a Monday morning when Brandon dispatches normally. Watch the dry-run email and confirm parses are correct.

---

## Validation gate (before going live)

Don't flip off the dry-run rail (Step 9) until **10 consecutive dispatches** parse correctly. Track them by reading the dry-run drafts — if all 10 propose the same actions Josh would have taken manually, we're safe to go live. If any one parses wrong, fix the parser prompt or matching logic and reset the counter.
