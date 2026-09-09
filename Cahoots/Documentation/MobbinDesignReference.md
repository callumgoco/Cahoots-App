# Mobbin design reference: Pushr iOS

## Access and scope

Reviewed on 7 August 2026 with the connected Mobbin MCP `search_screens` capability, not through a browser. The collection URL supplied in the brief is:

`https://mobbin.com/apps/pushr-ios-b9fbf2d1-5e5d-4c38-b77d-2f22efb506be/057a254e-7368-4961-ad06-c5cc18c95928/screens`

Four exclusion-paginated MCP requests returned 20, 20, 16, and 8 unique Pushr iOS screens. A fifth request excluding all 64 returned no screens, confirming that every screen exposed by the MCP search was reviewed. The set covered onboarding, permissions, setup completion, home metrics, weekly consistency, schedules, workout preparation, active/paused workout states, history and empty history, completion/streak feedback, settings, membership, feedback, and light/dark presentations.

Reviewed screen IDs:

`2d9dedab`, `48eddd1b`, `242f1cc3`, `29b31ea3`, `aa55ae53`, `bd1913f9`, `4c540f39`, `bba18edd`, `108d4e4a`, `870b3457`, `15b9ef05`, `31355fcb`, `1e4dd6e2`, `629cb9ad`, `3d789eaf`, `3d3f2655`, `a7f7ee88`, `73ddfeca`, `354d7b47`, `12905ba4`, `c60e28a6`, `599078a3`, `bad34b07`, `195330b0`, `a5c74235`, `9533f83f`, `4f74fc4c`, `86f091bc`, `2098b52d`, `18cdfc71`, `878dd59d`, `77bdde9c`, `50a35ef8`, `7565a64a`, `7c8e5492`, `e5c427f1`, `64fd84ab`, `be056d0f`, `b395bc04`, `ece8cca0`, `d84f81d4`, `107957d2`, `691db5f8`, `cfcc9e58`, `faf1d2d2`, `9d60a7a1`, `ca44452a`, `ebedf385`, `090363cb`, `36d1d597`, `d3d094ca`, `837cd1e5`, `73db58e2`, `7ec6b8c3`, `7a1dbda1`, `5cfa8827`, `8ee62cc2`, `b06889cf`, `222f884d`, `8ecd6858`, `c5181e05`, `5b9a5949`, `51005218`, `7586a76e`.

## Recurring visual patterns

- **Layout:** generous top whitespace, a direct title or brand anchor, one dominant metric module, supporting cards, and a bottom-reachable primary action. Active-workout screens strip away navigation and make one number the focal point.
- **Spacing:** approximately 18–20 pt horizontal page margins; card gaps around 8–12 pt; card padding around 14–18 pt; large empty areas are deliberate rather than filled with decoration.
- **Typography:** heavy rounded/display-like headings, compact sentence-case labels, tabular numerals, and very large quantities (roughly 56–112 pt in workout contexts). Secondary text is quieter but still readable.
- **Metrics:** the number leads, the unit follows, and comparison periods form a low visual shelf. Weekly consistency uses a compact row of day tokens.
- **Cards:** pale-grey/white modular rounded rectangles, usually 14–20 pt radius, subtle or absent borders, and soft shadows only when elevation clarifies hierarchy.
- **Buttons:** black/white high-contrast pills, large label weight, minimum 48 pt height; destructive workout controls use red sparingly.
- **Navigation:** shallow drill-in navigation; circular back/add/settings controls; high-frequency actions sit at the bottom. The reference relies more on contextual navigation than a dense tab bar.
- **Sheets/modals:** lower panels use a blurred/dimmed background, oversized corner radii, a concise heading, and adjacent secondary/primary actions. Completion feedback is similarly lightweight.
- **Appearance:** light mode is near-white with soft grey modules and black type. Dark workout/paywall screens invert the same hierarchy into black and charcoal rather than introducing many colours.
- **Empty states:** direct headline, short explanatory copy, and ample negative space; no decorative illustration is required for every absence.
- **Workout logging:** a single oversized changing count, minimal controls near the thumb, clear paused/active status, and a short review/completion step.
- **Motion:** the still collection implies numeric transitions, sheet movement, progress-token state changes, and blurred backdrop transitions. It does not suggest constant decorative animation.

## Inferred Cahoots tokens

| Token | Cahoots value | Reference rationale |
| --- | --- | --- |
| Page inset | 20 pt | Consistent narrow page gutters |
| Micro / small / medium / large gap | 4 / 8 / 16 / 24 pt | Compact internals with large section separation |
| Card radius | 22 pt | Soft modular silhouette, made slightly more distinctive |
| Control radius | 16 pt or capsule | Native, tactile actions |
| Hero metric | Dynamic 72 pt heavy, tabular | Immediate at-a-glance comprehension |
| Title | Dynamic 34 pt bold | Editorial hierarchy without a custom font |
| Card surface | system background elevated over grouped page | Native light/dark adaptation |
| Accent | restrained safety green | Used for progress/actions, never as broad decoration |
| Motion | 0.28 s responsive spring | Short and tactile; disabled/reduced where requested |
| Shadow | black 6% / 16 pt blur / 6 pt y | Limited to raised primary modules |

All type uses Apple system fonts. Values are semantic through Dynamic Type rather than fixed where text can grow.

## Patterns suitable for Cahoots

- One oversized daily target/progress number on Today and in the check-in sheet.
- Compact modular cards for deadline, streak, position, vote progress, and recent activity.
- A bottom-reachable pill action for logging a workout.
- Day tokens for daily/selected-weekday challenge rules.
- Calm, sheet-based completion feedback and subtle numeric transitions.
- Strong monochrome hierarchy with one restrained status/accent colour.
- Sparse empty states and clear native settings groups.

## Patterns deliberately not copied

- Pushr's name, distressed logo, written copy, illustrations, icon arrangements, brand assets, and exact card compositions.
- Camera-based automatic push-up tracking, HealthKit-specific promises, public global totals, and workout-set controls.
- Its paid-membership/paywall treatments and review solicitations.
- Guilt-oriented streak copy and delayed-workout warnings.
- Exact screen-level layouts, blurred background compositions, and membership-card design.

## Original adaptation

Cahoots applies the reference language to private social challenges rather than individual automatic tracking. The Today hero combines a target with deadline and group context; social accountability appears as privacy-safe activity, voting, recovery-day, and leaderboard modules. Rounded cards use an asymmetric metric grid and safety-green completion state. The four-tab native information architecture, proposal voting, invite flows, honour-system disclosure, recovery protections, and provisional offline scoring are original product structures driven by this brief.
