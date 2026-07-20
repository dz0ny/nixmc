# NixMC landing page

Marketing site for [NixMC](https://github.com/dz0ny/nixmc), built with Astro + Tailwind v4 + shadcn/ui (scaffolded by [Hakuto](https://hakuto.dev/)) and deployed to **GitHub Pages**.

## Develop

```sh
bun install
bun run dev
```

Open http://localhost:4321/nixmc/ (the site is served under the `/nixmc` base path).

## Build & preview

```sh
bun run build     # → dist/  (static site)
bun run preview   # serve the production build for review
```

## Deploy

Pushing to `main` with changes under `site/**` triggers `.github/workflows/pages.yml`
(at the repo root), which builds this folder and publishes `dist/` to GitHub Pages.

**One-time setup:** in the repo, go to **Settings → Pages → Source** and select
**GitHub Actions**. After the first successful run the site is live at
`https://dz0ny.github.io/nixmc/`.

### Custom domain later?

Set `site`/`base` in `astro.config.mjs` (e.g. `site: "https://nixmc.example.com"`,
`base: "/"`), add a `public/CNAME` file with the domain, and configure DNS.

## Stack

Astro 6 (static) · Tailwind CSS v4 · shadcn/ui · TypeScript · Biome · Bun · GitHub Pages

## Design

See `site-specification.md` for the design system (Minimalist/Light, teal accent from
the app icon, Space Grotesk + JetBrains Mono).
