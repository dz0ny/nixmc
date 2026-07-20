// @ts-check
import { readFile, writeFile, readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { defineConfig, fontProviders } from "astro/config";
import { imageService } from "@unpic/astro/service";
import { defineConfig as viteConfig } from "vite";
import react from "@astrojs/react";
import tailwindcss from "@tailwindcss/vite";
import sitemap from "@astrojs/sitemap";
import favicons from "astro-favicons";
import pagefind from "astro-pagefind";
import { agentsSummary } from "@nuasite/agent-summary";
import { astroGrab } from "astro-grab";

// astro-favicons hardcodes root-absolute ("/favicon.ico") URLs for every asset it
// injects (head links, manifest.webmanifest, browserconfig.xml). Under a project-site
// `base` those all 404. This post-build hook rewrites them to the configured base.
function faviconBaseFix() {
  let base = "/";
  return {
    name: "favicon-base-fix",
    hooks: {
      "astro:config:done": ({ config }) => {
        base = config.base.endsWith("/") ? config.base : `${config.base}/`;
      },
      "astro:build:done": async ({ dir }) => {
        if (base === "/") return;
        const distPath = fileURLToPath(dir);
        const entries = await readdir(distPath, {
          withFileTypes: true,
          recursive: true,
        });
        const assetRe =
          /^(favicon|apple-touch-icon|android-chrome|mstile-|safari-pinned-tab|yandex-browser|manifest\.webmanifest|browserconfig\.xml)/;
        const names = new Set(
          entries.filter((e) => e.isFile() && assetRe.test(e.name)).map((e) => e.name),
        );
        const targets = entries.filter(
          (e) => e.isFile() && /\.(html|webmanifest|xml|json)$/.test(e.name),
        );
        for (const e of targets) {
          const file = `${e.parentPath}/${e.name}`;
          let html = await readFile(file, "utf8");
          let changed = false;
          for (const name of names) {
            for (const q of ['"', "'"]) {
              const from = `${q}/${name}`;
              if (html.includes(from)) {
                html = html.split(from).join(`${q}${base}${name}`);
                changed = true;
              }
            }
          }
          // manifest start_url ("/?homescreen=1")
          if (html.includes('"/?homescreen')) {
            html = html.split('"/?homescreen').join(`"${base}?homescreen`);
            changed = true;
          }
          if (changed) await writeFile(file, html);
        }
      },
    },
  };
}

// GitHub Pages project site: https://dz0ny.github.io/nixmc/
// Static output, no server adapter.
// https://astro.build/config
export default defineConfig({
  site: "https://dz0ny.github.io",
  base: "/nixmc",
  output: "static",
  trailingSlash: "always",
  image: { service: imageService() },
  integrations: [
    react(),
    sitemap(),
    agentsSummary(),
    pagefind(),
    astroGrab(),
    favicons({
      input: "./src/assets/favicon.png",
      name: "NixMC",
      short_name: "NixMC",
    }),
    faviconBaseFix(),
  ],

  vite: viteConfig({
    cacheDir: ".astro/vite",
    plugins: [tailwindcss()],
    resolve: {
      alias: {
        "@": "/src",
      },
    },
  }),

  build: {
    concurrency: 4,
  },

  server: { port: 4321, host: "0.0.0.0", allowedHosts: true },
  devToolbar: { enabled: false },

  fonts: [
    {
      provider: fontProviders.google(),
      name: "Space Grotesk",
      cssVariable: "--font-grotesk",
      weights: ["300 700"],
      styles: ["normal"],
      subsets: ["latin"],
      fallbacks: ["ui-sans-serif", "system-ui", "sans-serif"],
    },
    {
      provider: fontProviders.google(),
      name: "JetBrains Mono",
      cssVariable: "--font-mono-code",
      weights: [400, 500, 700],
      styles: ["normal"],
      subsets: ["latin"],
      fallbacks: ["ui-monospace", "monospace"],
    },
  ],
});
