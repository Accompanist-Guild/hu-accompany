# Design

The site looks like the app on purpose: a dark "turntable room" that opens onto warm paper pages, with gold accents and the shelf's four card colours. Every colour, radius and shadow comes from the Flutter theme, so the two stay a family.

Sources in the app: `frontend/lib/shared/theme/Color_Theme.dart` (palettes) and `Design_Tokens.dart` (radii, spacing, shadows). If the app's theme changes, update the variables at the top of `site.css`.

## Tokens

All are CSS variables in `:root` at the top of `site.css`.

| Variable | Light value | Dark value | App source |
|---|---|---|---|
| `--bg` (page) | `#f7f2e7` | `#1b1b1f` | `PracticePalette.ivory` / `TurntablePalette.background` |
| `--paper` / `--surface` (cards) | `#fffcf4` | `#232327` | `PracticePalette.paper` / `TurntablePalette.mat` |
| `--text` | `#30271f` | `#ede6da` | `PracticePalette.brown` / `TurntablePalette.parchment` |
| `--muted` | `#75695b` | `#aaa294` | `PracticePalette.mutedBrown` (dark: tuned for contrast) |
| `--gold` | `#9a7a2c` | same | `PracticePalette.gold` |
| `--gold-text` (links, small gold text) | `#7d6122` | `#d8c58d` | darker gold for text on paper; `lightGold` in dark |
| `--light-gold` | `#d8c58d` | same | `PracticePalette.lightGold` |
| `--line`, `--code` | `#e6dcc6`, `#efe8d6` | `#36363b`, `#2d2d32` | derived |
| `--r-card`, `--r-lg`, `--r-modal` | 12px, 16px, 20px | same | `Radii.card`, `.lg`, `.modal` |

Four card gradients (the tiles on the home page) are the shelf's `ShelfPalette.cardGradients`: lavender `#9b8fc4 > #4a3f73`, teal `#5fa39f > #244744`, dusty rose `#d59aa3 > #7a414b`, sage `#9bc08a > #3e5934`.

## Type

The system font, as in the app: `-apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, system-ui, sans-serif`. Body 17px, line height 1.55. No web fonts, so there is no request to a font service and no flash of unstyled text. Headings use weight 700 and tight tracking; the small gold "kicker" above the title is uppercase with wide tracking.

## Layout

- Content column: 46rem maximum, 16px side gutters, no horizontal scroll.
- Home page: a dark `.room` header (rounded bottom corners) containing the title, a spinning vinyl record, and a frosted-glass panel with the Download button; paper sections below.
- Guides: a slim dark `.topbar`, breadcrumbs, then the article on the paper background.
- Breakpoints: the home-page tiles become one column under 30rem; the guide cards under 34rem.

## Components

| Class | What it is |
|---|---|
| `.room`, `.record` | The dark hero and the record. The record is pure CSS (repeating radial gradients plus a conic sheen), a gold label, and spins on a 9-second loop. |
| `.glass` | The download panel: translucent white, blurred backdrop, like the app's liquid-glass buttons. |
| `.button` | Pill button. Light gold with brown text on the dark hero. |
| `.tile` + `.teal`, `.lavender`, `.rose`, `.sage` | The four feature cards, each with a small disk. |
| `.card`, `ol.steps` | The install steps: numbered gold circles on a paper card. |
| `.callout`, `.note` | Highlighted notes. |
| `.guides`, `.guide` | The guide cards on the hub and home page. |
| `table.pages`, `details.qa`, `.pager`, `.crumbs`, `.topbar`, `.cta` | Guide furniture. |

Press feedback follows the app: a pill button scales to 0.97 for 120 ms.

## Dark mode

Automatic from the visitor's system setting (`prefers-color-scheme`). To force a mode while previewing, add `data-theme="dark"` or `data-theme="light"` to the `<html>` tag. Do not commit that attribute.

## Accessibility

Contrast ratios (WCAG 2.x, computed from the hex values above; 4.5:1 is the minimum for body text, 3:1 for large text):

| Pair | Ratio |
|---|---|
| Text on page / on card (light) | 13.1 / 14.3 |
| Muted text on page / on card (light) | 4.8 / 5.2 |
| Links on page (light) | 5.2 |
| Cream text on `--gold-text` (step numbers, guide button) | 5.7 |
| Brown text on light gold (hero button) | 8.6 |
| Text on page (dark) | 13.8 |
| Muted text on page / on card (dark) | 6.8 / 6.2 |
| Links on page (dark) | 10.1 |
| White on the tiles, where the text sits (gradient at 40% to 62%) | 4.6 to 10.2 |

Notes:

- The tile text sits in the lower half of each card, where the gradient is darkest. Teal and lavender are comfortably above 4.5:1 there. Rose and sage are 4.9 and 4.6 at the highest point the text reaches. Keep the text short, and do not move the text to the top of a tile.
- Decorative gold (`--gold` on its own) is about 3.9:1 on cream, below 4.5:1, so it is used only for decoration (rules, the dot under headings), never for text. Use `--gold-text` for any gold text.
- The spinning record stops when the visitor has asked for reduced motion (`prefers-reduced-motion: reduce`).
- Every link and button has a visible focus ring. The decorative record is hidden from screen readers (`aria-hidden`).
- Not tested with a screen reader or on a real phone: previews were headless Chrome at 420 to 900px.

## Rules for changes

1. Take new colours from the app's theme files, not from a colour picker.
2. Anything that sets text on a coloured background gets its contrast ratio checked (the table above shows how it was computed).
3. Keep it dependency-free: no fonts, images or scripts from other sites. The Content Security Policy will block them anyway.
4. Preview in light and dark, at about 420px and about 900px wide.
