# PostgreSQL Isolation Levels Lab — Reference Website

A [Nextra](https://nextra.site)-based, browsable handbook for the isolation demos in this repo. It mirrors the `sql/` demos and the `lessons/` teaching scripts as searchable reference pages — the "look it up later" companion to the interactive in-Cursor walkthrough.

## Development

```bash
# from the website/ directory
npm install
npm run dev
# open http://localhost:3000
```

## Building

```bash
npm run build
# Static output lands in out/. The postbuild step runs Pagefind to index it for search.
npm run preview   # serve the built out/ locally
```

## Tech stack

- **Next.js 14** — static export (`output: 'export'`)
- **Nextra 3** + `nextra-theme-docs` — docs theme, sidebar, MDX
- **Pagefind** — client-side full-text search (indexes `out/` after build)

## Structure

```
website/
├── pages/
│   ├── index.mdx               # Overview + isolation cheat-sheet
│   ├── _meta.ts                # Top-level nav
│   ├── getting-started/        # Isolation primer + environment setup
│   └── demos/                  # One reference guide per sql/0X_*.sql demo
├── styles/globals.css
├── theme.config.tsx
└── next.config.mjs
```

## Relationship to the rest of the repo

This site documents the same content as the `sql/` demo files and `lessons/*/SCRIPT.md`. It is a reference, not the primary delivery: the hands-on path is the `/start-*` interactive walkthrough (see the repo root `README.md`). When demos change in `sql/`, update the matching page under `pages/demos/`.

## Deployment

The site auto-deploys to GitHub Pages on every push to `main` via
[`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml). The workflow builds from this
`website/` directory (`npm ci && npm run build`, which also runs the Pagefind index step) and
publishes the static `out/` directory.

Live URL: <https://t7y.github.io/pg_isolation_levels/>

Because it deploys as a GitHub *project page* under `/pg_isolation_levels`, `next.config.mjs` sets a
production-only `basePath`/`assetPrefix` of `/pg_isolation_levels` and `trailingSlash: true`. The
empty `public/.nojekyll` file keeps GitHub Pages from stripping the `_next/` directory.

One-time setup: in the repo's **Settings → Pages → Source**, select **GitHub Actions**.

The static `out/` directory also deploys to any other static host. For Vercel: set the root directory
to `website`, build command `npm run build`, output directory `out` (and drop the `basePath`).
