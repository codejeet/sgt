# SGT Cockpit Redesign Rules

Issue: `#278`

This document captures the research-first design constraints for the next SGT cockpit refinement pass. It exists to keep follow-on UI work grounded in explicit anti-patterns and operator-facing heuristics instead of generic "make it look cooler" dashboard styling.

The current cockpit already proves the real-time shell, topology, blocker, and live stream functionality. The next pass should preserve that capability while making the interface feel more deliberate, more operator-first, and less like default AI-generated dashboard output.

## Inputs Considered

- the current repo-tracked cockpit markup and styling in `web/public/`
- the operator directives recorded in `SGT_CONTEXT.md`
- established information-design principles that consistently favor hierarchy, restraint, legibility, and signal-over-decoration in dense monitoring tools

This document therefore mixes:

- direct observations from the current SGT cockpit
- inferred "AI dashboard tells" that show up repeatedly in generated UI output
- concrete design rules for the follow-on implementation issue

## Current Tells To Remove

The current cockpit is functional, but several visible choices read as generated dark-dashboard defaults rather than as a human-designed operator console:

- `JARVIS Cockpit` branding leans into a stock sci-fi trope instead of a product-specific operating surface.
- large background gradients, glow layers, and blur create atmosphere before they create hierarchy.
- repeated pill shapes (`999px` radii) make controls, labels, and state chips feel interchangeable.
- Orbitron-heavy uppercase labeling pushes the shell toward costume instead of instrument.
- cyan-forward accents appear on too many elements, which weakens status meaning.
- alert, blocker, queue, and metric cards share nearly the same visual treatment, so the page feels uniformly styled instead of intentionally prioritized.
- the overview starts with Alert Center, which pulls the page toward inbox triage instead of live operations monitoring.

These are not functional bugs. They are stylistic tells that make the UI feel machine-composed.

## Anti-Pattern Catalog

### 1. Glow-first hierarchy

Symptom:
- gradients, bloom, blurred panels, and backlit borders do more work than spacing, grouping, and typography

Why it reads as AI-generated:
- generated dashboard mockups often reach for "high-tech" atmosphere before they solve scanning order

Rule:
- hierarchy must come from layout, contrast, alignment, and density first
- any gradient or glow must be subordinate and sparse

### 2. Maximum-rounding everywhere

Symptom:
- cards, chips, buttons, and panels all use heavily rounded corners or full pills

Why it reads as AI-generated:
- over-rounding is a common shortcut for making rough layouts feel "finished" without adding structure

Rule:
- default to square or barely rounded surfaces
- reserve stronger rounding only for a small number of touch targets if truly needed

### 3. Sci-fi naming and costume UI

Symptom:
- labels such as `JARVIS`, `radar`, `pulse`, or similar fiction-coded framing dominate the shell

Why it reads as AI-generated:
- generated concepts borrow familiar movie-control-room language because it signals "futuristic" quickly

Rule:
- use SGT-specific, operator-specific naming
- the visible title must read exactly `SGT SGT Cockpit`

### 4. Accent-color inflation

Symptom:
- one bright accent color appears in headings, borders, buttons, chips, and data emphasis simultaneously

Why it reads as AI-generated:
- generated dark UIs often spray a single neon accent across every component class

Rule:
- keep blue in the palette, but use a deliberate dark triadic system
- reserve stronger saturation for state change, focus, and true priority

### 5. Typography-as-effect

Symptom:
- wide uppercase display text appears across large portions of the shell

Why it reads as AI-generated:
- generated dashboards often use display typography as a substitute for information design

Rule:
- use display typography sparingly
- body, metadata, and dense controls should read like tooling, not poster art

### 6. Uniform card language

Symptom:
- every panel becomes a bordered, tinted, glowing card with similar spacing and weight

Why it reads as AI-generated:
- component sameness is a common output of prompt-driven design systems with no editorial judgment

Rule:
- panels should vary by job: live monitor, blockers, queue, and topology should not all feel equivalent
- section framing must reflect actual operator priority

### 7. Decoration over state semantics

Symptom:
- accent colors and effects are used decoratively, making health, stale, blocked, and critical states less distinct

Why it reads as AI-generated:
- visual flourish consumes the same channels that real monitoring state should use

Rule:
- preserve semantic color discipline
- healthy, active, stale, blocked, and critical states need stable mappings that survive theme changes

### 8. "Dashboard collage" layout

Symptom:
- the page opens as a collage of cards instead of with a single operational focal plane

Why it reads as AI-generated:
- generated dashboards often optimize for screenshot variety instead of task order

Rule:
- the live monitoring section must be the first major section operators encounter
- alerts remain visible, but they cannot own the first-read hierarchy

## Human-Designed Heuristics To Prefer

- Start from operator task order, not screenshot drama.
- Make one section clearly primary on first load.
- Use spacing and alignment before effects.
- Let panels earn visual weight through function.
- Keep data density readable instead of cinematic.
- Use fewer visual motifs, repeated more consistently.
- Give color explicit jobs: status, focus, warning, blockage, success.
- Keep novelty at the edges; keep monitoring surfaces boring in the good sense.

## Explicit Redesign Rules

The follow-on implementation should treat these as requirements, not suggestions:

1. The first major section on page load must be live monitoring, not the alert center.
2. The visible operator-facing title must read exactly `SGT SGT Cockpit`.
3. Remove visible `Jarvis Cockpit` branding from the shell.
4. Materially reduce gradients, glows, and glass/blur styling.
5. Materially reduce corner radius across panels, cards, chips, and buttons.
6. Keep the interface dark, but move to a stronger triadic palette that still includes blue.
7. Use color more intentionally and less uniformly; not every interactive or bordered element should glow blue.
8. Differentiate the visual treatment of live monitoring, blockers, queue, topology, and dispatch according to operator priority.
9. Preserve existing live monitoring, blocker awareness, topology, and operator-shell behavior.
10. Keep repo `web/` as the canonical source and document the sync path to `/root/sgt/web`.

## Section-Specific Direction

### Live monitor

- make it the first read and the strongest surface
- optimize for freshness, state, and readable terminal content
- avoid decorative wrappers that compete with the stream itself

### Alerts and blockers

- keep them prominent, but secondary to the live monitor
- use stricter severity semantics and less ornamental styling
- resolution, escalation, and open-blocker states should read differently at a glance

### Topology

- treat it as an orientation tool, not as the hero visual
- simplify supporting chrome so the graph relationships do the work

### Dispatch and logs

- keep them utilitarian
- avoid styling them like trophy panels

## Concrete Style Prompts For The Follow-on Implementation

Use prompts/rules shaped like this when designing or reviewing the next pass:

- "Design this as a human-operated control room, not a sci-fi concept render."
- "Prioritize monitoring hierarchy, panel purpose, and state clarity over atmosphere."
- "Use a dark triadic palette with restrained blue, amber, and a third accent, but keep most surfaces low-chroma."
- "Prefer flat or lightly textured surfaces over glow, blur, and large gradients."
- "Use mostly square geometry with only slight rounding."
- "Make the live monitor feel like the instrument panel; everything else supports it."
- "Avoid glassmorphism, neon bloom, oversized pills, and generic AI-dashboard chrome."
- "If a style choice looks good in a hero screenshot but weakens scanning, remove it."

## Review Checklist For The Next Issue

- Is live monitoring the first major section on the page?
- Does the title read `SGT SGT Cockpit`?
- Has the visible sci-fi/JARVIS framing been removed?
- Are gradients and glow effects materially reduced?
- Are corner radii materially reduced?
- Is the palette dark, triadic, and still inclusive of blue?
- Do panel types now feel intentionally differentiated?
- Are blocker, topology, and dispatch capabilities still intact?
- Do docs still explain repo `web/` to `/root/sgt/web` sync?

If any answer is "no", the redesign is incomplete.
