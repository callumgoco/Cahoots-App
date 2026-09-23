# Mobbin design reference: Pushr iOS

## Access and scope

Collection URL:

`https://mobbin.com/apps/pushr-ios-b9fbf2d1-5e5d-4c38-b77d-2f22efb506be/057a254e-7368-4961-ad06-c5cc18c95928/screens`

**First review (7 August 2026):** four exclusion-paginated `search_screens` requests returned 20, 20, 16, and 8 unique Pushr iOS screens (64 total). A fifth request excluding all 64 returned none.

**Live re-review (11 September 2026):** Mobbin MCP `search_screens` + `search_flows` with image inspection. Covered home, workout complete/pause/new-set, history, settings, schedule/reminders (including the sliding time picker), onboarding, PRO subscribe, dark-mode workout, and camera-view switch. Key flows:

- [Home](https://mobbin.com/flows/c6235b1d-344f-4a96-85cd-872aef2f5658)
- [Completing a workout](https://mobbin.com/flows/2d9edf73-c1d5-4a0d-afa9-eff7668b85cd)
- [Pausing a workout](https://mobbin.com/flows/114e0467-df98-4752-bcca-cb05af51bf06)
- [History](https://mobbin.com/flows/19c77547-6987-4268-b1bc-8abd3f4dbc36)
- [Scheduling a reminder](https://mobbin.com/flows/73728b15-23f6-4cf4-81d8-51c3c616e266)
- [Settings](https://mobbin.com/flows/ceebe27b-c344-4143-b0b7-f6b507488b64)
- [Onboarding](https://mobbin.com/flows/bdc848ab-0394-418e-8868-667ddce96ebf)
- [Subscribing to pushr PRO](https://mobbin.com/flows/49cc8387-091a-48af-8a71-c2c34f6490e0)
- [Switching to dark mode](https://mobbin.com/flows/078ae9e2-c499-4236-afd6-0d58f5e63c14)

Representative screens: [home](https://mobbin.com/screens/2d9dedab-7961-4927-ada0-5d9338d95bf7), [active workout](https://mobbin.com/screens/9d60a7a1-9174-4a5f-843e-ffb197a0f299), [completion card](https://mobbin.com/screens/4c540f39-b290-41c8-8f67-2274b8deb153), [history](https://mobbin.com/screens/36d1d597-ef52-4d21-92ec-f7ba6a0394d4), [schedule](https://mobbin.com/screens/7565a64a-27af-4c69-8ea8-e58ab1f02c54), [new schedule sheet](https://mobbin.com/screens/2098b52d-fc98-4f43-9e8f-060afb1ed79d), [settings](https://mobbin.com/screens/4f74fc4c-589c-40ab-8c39-d93935c8d313).

## Feature map (from live flows)

| Area | What Pushr does |
| --- | --- |
| Home | Daily count hero + week/month/lifetime shelf; week day tokens with streak flame; optional black “global push-ups” card; floating “start workout” pill + history affordance |
| Workout | Countdown → oversized live count with reflection; floating timer/pause pill; separate red stop circle; pause state; new-set; camera / dark (moon) toggles |
| Completion | Blurred backdrop + white summary card (hero reps + 3-col micro-stats); Health confirm; share / Instagram icons; glass “next” pill |
| History | Date-sectioned list; large count left, black duration pill right; detail modal over blur |
| Schedule | Circular back/add; schedule cards with grey time chips + green active check; sheet with day circles + **horizontal ruler time dial** |
| Settings | Card groups (notifications, health, social toggle, PRO); circular back; lowercase titles |
| Monetization | PRO paywall / membership card (do not copy) |

## Recurring visual patterns

- **Layout:** generous top whitespace, a direct title or brand anchor, one dominant metric module, supporting cards, and a bottom-reachable primary action. Active-workout screens strip away navigation and make one number the focal point.
- **Spacing:** approximately 18–20 pt horizontal page margins; card gaps around 8–12 pt; card padding around 14–18 pt; large empty areas are deliberate rather than filled with decoration.
- **Typography:** heavy display numerals; **bold lowercase** UI labels (“start workout”, “settings”, “schedule”); tabular / monospaced timers; workout counts roughly 56–112 pt. Secondary text is quieter grey.
- **Metrics:** the number leads, the unit follows, and comparison periods form a low visual shelf (week / month / so far). Weekly consistency uses **vertical black day pills** with checkmarks (not only dots).
- **Cards:** pale-grey/white modular rounded rectangles (~14–24 pt radius), soft shadows; one inverted black card used for community emphasis.
- **Buttons:** black/white high-contrast pills; floating primary CTA; circular chrome for back/add/camera; red reserved for stop/delete.
- **Navigation:** shallow drill-in; no dense tab bar on home — one primary CTA + secondary history icon.
- **Sheets/modals:** blurred background, oversized corner radii, adjacent delete/done pills, day-circle multi-select + sliding time ruler.
- **Appearance:** light near-white + soft grey modules; workout dark mode is pure black/white with the same control geometry.
- **Empty / sparse states:** headline, short copy, negative space; no obligatory illustration.
- **Motion (inferred):** numeric transitions, day-token fills, sheet blur, countdown, reflection under the live count.

## Inferred Cahoots tokens

| Token | Cahoots value | Reference rationale |
| --- | --- | --- |
| Page inset | 20 pt | Consistent narrow page gutters |
| Micro / small / medium / large gap | 4 / 8 / 16 / 24 pt | Compact internals with large section separation |
| Card radius | 22 pt | Soft modular silhouette, made slightly more distinctive |
| Control radius | 16 pt or capsule | Native, tactile actions |
| Hero metric | Dynamic 72 pt heavy, tabular | Immediate at-a-glance comprehension |
| Title | Dynamic 34 pt bold | Editorial hierarchy without a custom font |
| Card surface | theme invert (charcoal on soft page) | Cahoots adaptation of Pushr’s light/dark card hierarchy |
| Accent | restrained semantic green / amber / red | Status only — never broad decoration |
| Motion | 0.28 s responsive spring | Short and tactile; reduced-motion aware |
| Shadow | black 6% / 16 pt blur / 6 pt y | Limited to raised primary modules |

All type uses Apple system fonts. Values are semantic through Dynamic Type rather than fixed where text can grow.

## Patterns suitable for Cahoots

### Already adopted

- Oversized daily / session metric and countdown poster on Today.
- Week day-token strip (`WeekStrip`) with **vertical filled capsules**.
- Capsule primary/secondary CTAs (~52–54 pt).
- Card radius, page inset, soft elevation shadow.
- Check-in focus flow (prep → countdown → record → review → reveal).
- Sparse empty states; sheet footers / bottom insets on several flows.
- Monochrome hierarchy + restrained semantic accents (mint/charcoal invert).
- **Thumb-sticky Today CTA** (`safeAreaInset` Log workout / Finish workout).
- **Metric shelf** under the Today hero (rank · streak · recovery left / points).
- **Floating session controls** — timer capsule + separate red stop; circular flip chrome.
- **Blurred completion / confirm** — raised summary card over material backdrop.
- **Sliding deadline dial** in challenge builder (`SlidingTimeDial`).
- **Circular chrome** on session flip and Crew menu.
- **Inverted crew emphasis card** (“N of M showed up”) on Crew.

### Still worth borrowing (later)

1. **History / activity row recipe** — large count left + high-contrast status/duration pill right; date section headers in quiet caps.
2. **Schedule card + time chip** — grey time pill + green active check for reminder / deadline rows in Profile or Crew settings.
3. True pause/resume during capture (visual chrome only today; product does not pause recording).

## Patterns deliberately not copied

- Pushr's name, distressed/glitch logo, written copy, illustrations, icon arrangements, brand assets, and exact card compositions.
- Camera-based automatic push-up tracking, HealthKit as a core promise, public global totals, and dense workout-set chrome.
- Paid-membership / paywall treatments, membership card, and review solicitations.
- Guilt-oriented streak copy and delayed-workout warnings.
- Exact screen-level layouts and membership-card design.
- Reflection / Metal distortion as brand identity (optional subtle depth only if it stays calm).

## Original adaptation

Cahoots applies the reference language to private social challenges rather than individual automatic tracking. The Today hero combines a target with deadline and group context; social accountability appears as privacy-safe activity, voting, recovery-day, and leaderboard modules. Rounded cards use an asymmetric metric grid and safety-green completion state. The four-tab native information architecture, proposal voting, invite flows, honour-system disclosure, recovery protections, and provisional offline scoring are original product structures driven by this brief.
