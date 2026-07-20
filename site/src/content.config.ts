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
		title: z.string(),
		section: z.string(),
		summary: z.string(),
		symbol: z.string().optional(),
		featured: z.boolean().default(false),
		source: z.string().url().optional(),
	}),
});

export const collections = { recipes };
