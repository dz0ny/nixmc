# Site Specification — NixMC landing page

## Configuration
- **Site Type**: SaaS (product-led, single-page landing for a macOS app)
- **Design Language (Starting Point)**: Minimalist / Light
- **Target Audience**: Mac users who want nix-darwin's reproducibility without hand-editing Nix; existing Nix users wanting a focused daily-driver UI; developers using Claude Code / Codex CLI
- **Primary Goal**: Download conversion (signed DMG) + GitHub source visits

## Deployment
- **Host**: GitHub Pages, project site at `https://dz0ny.github.io/nixmc/`
- **Astro config**: `site: "https://dz0ny.github.io"`, `base: "/nixmc"`, `output: "static"`, no server adapter (Cloudflare adapter + worker/ removed from scaffold)
- **CI**: `.github/workflows/pages.yml` (repo root) builds `site/` with Bun and publishes via `actions/deploy-pages`
- **Manual step required once**: repo Settings → Pages → Source = "GitHub Actions"

## Design Evolution
- **Starting aesthetic**: Minimalist / Light — clean paper-white background, charcoal ink, generous whitespace, subtle grid + radial glow in the hero, soft/lifted shadows on cards and screenshots
- **User customizations**: Accent color pulled from the app icon (metallic teal cube on charcoal) instead of a generic blue
- **Current style**:
  - **Colors**: background `hsl(210 24% 99%)`, ink/foreground `hsl(220 24% 12%)`, brand teal `hsl(183 46% 39%)`, steel `hsl(205 24% 46%)`. Dark-mode tokens defined but the page ships light by default.
  - **Typography**: **Space Grotesk** (variable 300–700) used decisively for headings + body; **JetBrains Mono** for terminal/command mock, code, eyebrow labels, and step numbers. Wired via Astro Fonts API (Google provider, self-hosted woff2, preloaded).
  - **Layout**: sticky blurred header; hero with badge → h1 → subhead → dual CTA → trust row → command mock → product screenshot; bento 3-col features grid; 5-step "how it works" strip; two-column recipes section (copy + guide screenshot); requirements + install (with local-build code block); dark CTA panel; 4-column footer.
  - **Motion**: CSS-only staggered `rise`/`fade` reveals on hero load (animation-delay ladder). No JS islands beyond static-rendered lucide-react SVGs.

## Recipes catalog
- **Source of truth**: the app's own recipe markdown, read at build time via an Astro
  content collection (`src/content.config.ts`) with a glob loader based at
  `../Sources/nixmc/Resources/recipes` — no copy, always in sync. Works in CI because
  the Pages workflow checks out the whole repo.
- **Sections**: `src/recipeSections.ts` defines the 15 sections in the app's order,
  each with a lucide icon and blurb; names match the `section:` front matter.
- **Homepage** (`components/Recipes.astro`): intro + guide screenshot + a live grid of
  the 15 section cards (icon, name, count, blurb) linking into the catalog, plus a
  "Browse all N recipes" button. Count is derived from the collection.
- **`/recipes/` page** (`pages/recipes.astro`): full catalog — 95 recipes grouped by
  section (featured first, then alphabetical), each a card with title/summary/featured
  badge linking to its `source:` URL, or the file on GitHub when no source is set.
  Sticky section jump-nav at the top.

## Assets
- `src/assets/nixmc-icon.png` — app icon (header, footer, favicon source)
- `src/assets/screenshot-recipes.png` — hero product shot
- `src/assets/screenshot-guide.png` — recipes section shot
- Copied from repo `Assets/` at build-setup time.

## Agent readiness
- `public/llms.txt` customized for NixMC
- `public/robots.txt` allow-all + absolute sitemap URL
- `AGENTS.md` auto-generated on build; `ENABLE_WEBMCP` left off (no Pagefind UI surface)
