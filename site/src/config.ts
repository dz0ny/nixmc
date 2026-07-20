// Static site config — hardcoded (no import.meta.env at build time).
export const SITE = {
	name: "NixMC",
	repo: "https://github.com/dz0ny/nixmc",
	releases: "https://github.com/dz0ny/nixmc/releases",
	latestDmg: "https://github.com/dz0ny/nixmc/releases/latest/download/nixmc.dmg",
	tagline: "Manage your Mac by describing the change you want.",
} as const;

// Base path for internal links (GitHub Pages project site → "/nixmc/").
export const BASE = import.meta.env.BASE_URL;
