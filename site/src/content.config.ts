import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";

// Read the app's built-in recipes straight from the repo source — no copy,
// always in sync at build time. The Pages workflow checks out the whole repo,
// so `../Sources/...` resolves in CI too.
const recipes = defineCollection({
	loader: glob({
		pattern: "**/*.md",
		base: "../Sources/nixmc/Resources/recipes",
	}),
	schema: z.object({
		// Stable front-matter id the macOS app keys recipes by (e.g. `ai-rtk`).
		// Used to build `nixmc://recipe/<id>` deep links; the glob entry `id` is
		// the file path, which the app doesn't know about.
		id: z.string().optional(),
		title: z.string(),
		section: z.string(),
		summary: z.string(),
		symbol: z.string().optional(),
		featured: z.boolean().default(false),
		source: z.string().url().optional(),
	}),
});

export const collections = { recipes };
