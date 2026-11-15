# Design

The visual rules for parc-ferme. The source of truth is the mockups:
[`design/mockups.html`](design/mockups.html) (mobile, 375 px) and
[`design/desktop.html`](design/desktop.html) (desktop, 1280 px). The tokens live in
[`app/assets/tokens.css`](app/assets/tokens.css). When this file and the mockups disagree,
the mockups win. Update this file afterwards.

## Concept

A dark timing screen. The UI is mostly neutral greys, so colour always means something:

- **Purple** means the best of the weekend: the top score, the brand accent, the input caret.
- **Green** means open, live or gained: the picks-open pill, "saved", a move up the table.
- **Yellow** means locked: the lock pill, the lock card, the locking session in the schedule.
- **Red** means lost: a move down the table. Use it for nothing else.
- **Team colours** carry driver identity. They appear only as a thin bar next to the driver.

Never use one of these colours as decoration.

## Tokens

Use the CSS custom properties. Don't write hex values in components.

| Token | Value | Use |
|---|---|---|
| `--canvas` | `#08090b` | Behind the app (mockup pages only, not yet in `tokens.css`) |
| `--bg` | `#0e0f12` | App background; also the text colour on a primary button |
| `--surface` | `#16181d` | Cards, inputs, pick slots, sheets, modals |
| `--surface-2` | `#1d2026` | Avatars, the selected segment |
| `--line` | `#262a31` | Every border and divider |
| `--ink` | `#eceef1` | Main text, primary button fill, the active state |
| `--muted` | `#8a909b` | Secondary text, labels |
| `--faint` | `#5c626d` | Hints, table headers, inactive tabs, points hints |
| `--purple` | `#a55cff` | Best of weekend, brand accent |
| `--green` | `#2fd27a` | Open, live, saved, gained |
| `--yellow` | `#f2c230` | Locked |
| `--red` | `#ff6b6b` | Position lost |

Tints are the token hex plus an alpha suffix:

- Pill and badge fills: about 10–12% (`#2fd27a1a`, `#a55cff1f`).
- Lock card border: `#f2c23055`. Lock card fill: a gradient from `#f2c2300f` to transparent.
- Highlighted rows ("me", selected): `#eceef10a` to `#eceef10f`.
- Empty and dashed borders: `#3a3f48`.

Two textures from the mockups are not yet in `tokens.css`. Copy them from the mockups when needed:

- `--grain`: an SVG noise texture on the app background, at 5% opacity.
- `--check`: a chequered-flag `conic-gradient`, used at 8–10% opacity and masked to fade out.

## Typography

| Token | Font | Use |
|---|---|---|
| `--display` | Barlow Condensed | Titles, the wordmark, sheet and modal headings. Always 700 weight and uppercase. |
| `--body` | IBM Plex Sans | Running text, buttons, form labels, names |
| `--mono` | JetBrains Mono | Numbers, driver codes, positions, pills, labels, eyebrows, table headers |

The base is `15px/1.5` in `--body`.

- **Numbers are always mono.** Countdowns, points, ranks and times use `--mono`. Totals use `font-variant-numeric: tabular-nums`.
- **Small labels are mono, uppercase and tracked.** Use 11–13 px with `letter-spacing` from `.08em` to `.12em`. This covers eyebrows, pills, section labels and table headers.
- **Driver codes** (VER, NOR) use 700 weight mono.

| Role | Mobile | Desktop |
|---|---|---|
| Wordmark | 84 px, line-height .86 | 100 px, line-height .84 |
| Page title | 36 px | 56 px |
| Form or auth heading | — | 44 px |
| Sheet or modal heading | 28 px | 34 px |
| Countdown digits | 40 px mono | 44 px mono |

The wordmark puts the second word in `--purple`: `PARC <span>FERME</span>`.

## Layout

- **Mobile:** 20 px side padding and 20 px vertical gap between blocks. A bottom tab bar has two tabs, Picks and Leaderboard. Profile opens from the avatar at the top right.
- **Desktop:** a 64 px top app bar holds the brand, the nav and the avatar. The active nav item has a 2 px `--ink` underline. The main area is a `1fr 360px` grid with a 40 px gap and `32px 40px` padding. The right rail holds the schedule and the rules.
- **Auth screens on desktop:** a split layout. On the left is art: a grid, a chequered strip and the circuit. On the right is a 520 px form column. Sign in, create account and check email all use this layout, so the page doesn't jump between them.
- **Full-bleed lists** (tables, the leaderboard, the driver list) cancel the side padding with a negative margin. Rows are separated by `--line` borders, not gaps.

## Shape

| Element | Radius |
|---|---|
| Pills | 6 px |
| Driver chips (desktop) | 10 px |
| Search, segmented control | 12 px |
| Inputs, buttons, pick slots | 14 px mobile, 12 px desktop |
| Cards | 16 px |
| Countdown, lock card | 18 px mobile, 16 px desktop |
| Modal | 20 px |
| Bottom sheet | 28 px, top corners only |
| Avatars, close button | 50% |

Every surface has a 1 px `--line` border. There are no drop shadows inside the app, except on modals and floating preview cards.

## Components

- **Button:** 54 px tall on mobile, 50 px on desktop, 600 weight body font.
  - `primary` has an `--ink` fill and `--bg` text.
  - `ghost` is transparent with a `--line` border.
  - The Google button follows Google's dark style: `#131314` fill, `#e3e3e3` text and a `#8e918f` border.
- **Input:** same height and radius as a button, with a `--surface` fill. The label sits above it at 13 px in `--muted`. Placeholder text is `--faint`.
- **Pill:** mono, uppercase, with a 1 px border in `currentColor` and an optional 7 px dot.
  - `open` is green and `lock` is yellow.
  - `live` is green with a tinted fill and no border.
- **Driver tag (`.drv`):** a 4×16 px bar in the team colour (2 px radius), followed by the driver code in mono. Inside tables the bar shrinks to 3×14 px.
- **Pick slot:** a row with a position column (P1, POLE…) divided off by a `--line` border, then the driver and name, then the points hint.
  - An empty slot is transparent with a dashed `#3a3f48` border.
  - The active slot has an `--ink` border.
  - On desktop the podium is laid out P2 · P1 · P3, with step heights of 160, 186 and 140 px.
- **Countdown card:** a dark gradient (`#1a1c21` to `#121418`) with a faded chequered pattern on the right.
- **Lock card:** a yellow-tinted border and gradient. It replaces the countdown once picks lock.
- **Driver picker:** a bottom sheet on mobile, with a grabber, a search field and a list. On desktop it is an 820 px modal that shows the whole grid grouped by team.
  - A driver already picked is shown at 40–45% opacity and labelled with the position it was given.
  - The selected driver gets a `#eceef10d` fill.
- **Leaderboard row:** rank, name, the movement (green ▲ or red ▼), last-race points and total.
  - Last-race points turn purple on a purple tint when they are the best of the weekend.
  - Your own row gets a light tint and a 3 px `--ink` inset bar on the left.
- **Segmented control:** a `--surface` track. The active segment uses `--surface-2` with a faint inset highlight.
  - On the leaderboard it switches between the season and the last race.
  - On a sprint weekend it also switches the Picks screen between Grand Prix and Sprint. Each has its own countdown or lock card, because each locks at its own qualifying.
- **Schedule row (desktop rail):** the session that locks picks gets a 3 px yellow inset bar. Sessions already finished are shown in `--faint`.

## States

- **Active or selected:** an `--ink` border or underline. Don't use a coloured accent for this.
- **Disabled or taken:** reduce opacity to 40–45%. Don't hide the item.
- **Empty:** a dashed border on a transparent background, with `--muted` text.
- **Saved:** a green dot and "Saved" in `--muted`. Picks save on selection, so there is no save button.

## Writing

- Labels and titles are short and uppercase through CSS. Write the source text in normal case.
- Explanatory copy says exactly what happens next. For example: "Open the link on this device".
- Position names are P1, P2, P3 and POLE.
- A race is a "Grand Prix" or a "Sprint". Points hints show that race's own values: +4, +2, +2 and 2 for a Grand Prix, +2, +1, +1 and 1 for a Sprint.

## Not decided yet

- Light mode. The design is dark only (`color-scheme: dark`).
- **An error state.** Red means "position lost" and nothing else, so a failed save, a form error and an expired sign-in link have no rule yet.
- **A results screen.** The mockups show picks open and picks locked, but not picks scored: your picks against the result, with the points each pick earned.
- **A season switch** on the leaderboard, for past seasons.
- **A keyboard focus ring.** Active and selected use an `--ink` border, so focus needs a different mark.
- **Other empty states:** no entry list yet, a cancelled race, results not published yet, and the off-season.
- **`--faint` contrast.** On `--bg` it is about 3.1:1, below the 4.5:1 that WCAG AA asks for small text. Table headers and inactive tabs use it at 11–13 px. Either move those to `--muted` or lighten `--faint`.

## Sources

- Fonts load from Google Fonts in [`index.html`](index.html). The loaded weights are Barlow Condensed 500–700, IBM Plex Sans 400–600 and JetBrains Mono 400/500/700. A new weight must be added there too.
- Team colours come from OpenF1's `team_colour`, which `sync-calendar` stores. Don't hard-code them in components.
