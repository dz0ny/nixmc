// @ts-check
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
