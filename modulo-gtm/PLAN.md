# Modulo (Pediatric Forms SaaS) — Go-To-Market Plan (Bootstrapped)

**Product (current):** pediatric-focused digital intake forms: packet builder → SMS/email delivery → mobile fill (EN/ES) → staff dashboard, audit logs.

**Current state (from Scearpo):**
- Used internally across ~23 clinics (single medical group). 0 external MRR.
- Gaps for selling: multi-tenancy, Stripe billing, HIPAA program (BAAs/policies/audit).

---

## 0) The hard truth (positioning constraint)
If Modulo stores ePHI and you’re selling to US medical practices, you need to be able to sign a **BAA** and have a credible HIPAA posture. Many small practices will still buy if you’re early, but you must be honest:
- either **don’t touch PHI** (proxy to EHR / patient portal / practice systems) 
- or **be HIPAA-ready enough** (BAAs + baseline controls + documented policies) to pass the “are you compliant?” question.

So the fastest bootstrapped GTM is:
- **Phase 1:** sell to *smaller practices* with a clear “baseline safeguards in place; full HIPAA program still being completed” posture.
- **Phase 2:** once multi-tenant + billing + policies are mature, expand.

### HIPAA messaging guardrails (use this exact stance)
- Do not claim “HIPAA compliant.”
- Say what exists today: encryption in transit/at rest, role-based access, audit logging, and incident response owner.
- Say what is still missing/in progress: signed BAAs across all sub-processors, finalized written policies/runbooks, formal third-party assessment.
- Use language like: “We are building toward full HIPAA readiness; here is our current baseline and open gaps.”

---

## 1) ICP (ideal customer profile)
### Primary ICP (fastest to close)
- Independent pediatric practices (1–5 providers)
- 1–3 locations
- High volume of new patients / recurring well-child visits
- Front-desk pain: printing/scanning, missing forms, rework, long check-in times

### Secondary ICP
- Pediatric groups (6–20 providers) that want standardized packets across locations.

**Buyer:** Practice owner / managing physician + practice manager.

**Economic pain:** staff time + patient throughput + bad experience.

---

## 2) Offer design (what you sell)
### The *only* promise that matters
**“Reduce check-in paperwork and staff rework via mobile intake packets sent by SMS.”**

### Core differentiators (keep it simple)
1) Pediatric-specific packet templates (well-child, sports, school, sick)
2) Best-in-class *builder precision* (your 192 DPI / field precision) → fewer errors
3) SMS-first delivery + completion tracking

Avoid over-claiming (“AI”, “automation”, etc.). Sell operational relief.

---

## 3) Pricing strategy (bootstrapped)
Scearpo proposed:
- $150/mo (1–2 providers)
- $300/mo (3–5)
- $500/mo (6+)
Per-location pricing.

### Recommendation
Start with **one price** to reduce friction:
- **$199/mo per location** (includes up to 5 providers) 
- +$49/mo per additional provider beyond 5

Why: one number is easier on cold call; still captures bigger clinics.

### Free trial vs money up front?
**Recommendation:**
- Offer a **14-day free trial** with “white-glove setup” conditional on a kickoff call.
- **Do NOT give it free outright** to random practices; you’ll drown in support.
- You *can* offer “founding clinic pricing” (locked rate) for the first N clinics.

### Referral/invite program
After first 5 paying clinics:
- “Invite another practice → both get 1 month free”
Keep it dead-simple.

---

## 4) Development roadmap needed for GTM
### Phase A — Sellable MVP (2–4 weeks)
Goal: close 3–5 paying clinics safely.

1) **Multi-tenancy** (must-have)
   - Tenant isolation for data, configs, templates
   - Per-tenant domain/path
   - Tenant admin + roles
2) **Billing (Stripe)**
   - Subscription + trials
   - Dunning (failed payments)
3) **HIPAA baseline** (minimum credible posture)
   - BAAs: AWS + any vendors touching ePHI
   - Documented policies: retention/deletion, access controls, breach response
   - Admin logs + access logging
   - Security contact + incident workflow
   - A simple “HIPAA posture” one-pager you can send prospects (baseline + gaps, no compliance claim)

### Phase B — Conversion + retention (2–6 weeks)
4) Packet templates library (pediatric defaults)
5) Staff dashboard polish (completion rates, resend flows)
6) “Save as template” + quick packet cloning

### Phase C — Scale (later)
7) Twilio migration if GoTo/Jive is limiting
8) EHR integrations (only when demanded)
9) Formal audit/pentest when enterprise pipeline exists

---

## 5) Bootstrapped acquisition channels (ranked)
### Channel 1: Cold calling (best)
- Build a list of pediatric clinics by state/city (Google Maps + NPI registry + directories)
- Call practice manager/front desk
- Goal: book a 15-minute demo with owner/manager

### Channel 2: Cold email (supporting)
- Email is harder now; still useful as follow-up after call

### Channel 3: Local partnerships
- Pediatric billing consultants, practice managers groups, local medical associations

### Channel 4: “Done-for-you” switch service
- Offer “we rebuild your packet templates for you in 48 hours”

---

## 6) Sales process (simple, repeatable)
1) **Cold call → permission-based opener** (Jeremy Miner style)
2) Qualify quickly:
   - how do they do intake now?
   - volume? staff time?
   - do they text patients?
3) **Demo** (15 min):
   - show SMS link → patient mobile UX
   - show staff completion dashboard
   - show packet builder *briefly*
4) Close:
   - 14-day trial + $199/mo after
   - white-glove setup call scheduled immediately

---

## 7) Metrics to track (don’t fly blind)
**Top-of-funnel:**
- Dials/day, connects/day, demos booked/week

**Activation:**
- Time-to-first-packet
- Time-to-first-successful-patient-completion

**Retention:**
- Packets sent per week per clinic
- % completion rate

**ROI story:**
- Staff minutes saved/week

---

## 8) Suggested “best plan of action”
**Do not do the ‘young developer asking advice’ angle** as the primary pitch. It can get you conversations, but it weakens authority and makes procurement weird.

Instead:
- Lead with **operational pain relief**
- Offer a **trial** with a concrete success criterion: “In 14 days we’ll get X% of your patients completing intake on mobile before arrival.”

The “asking advice” angle can be a *fallback* opener if they’re busy:
- “Could I ask you a quick question—what’s the biggest headache with intake paperwork today?”

---

## 9) Action plan (next 14 days)
### Day 1–2
- Finalize pricing (one number)
- Create 1-pager HIPAA posture + BAA status
- Prepare 3 demo packets (well-child/sports/sick)

### Day 3–7
- Ship multi-tenancy + Stripe trial
- Build list of 200 clinics (one metro area + surrounding)
- Start calling: 50 dials/day

### Day 8–14
- Run demos + onboard 3 trials
- Convert 1–2 to paid
- Collect testimonial + before/after metrics

---

# Appendix A: Cold calling script (Jeremy Miner-inspired)
See `COLD_CALL_SCRIPT.md`.
