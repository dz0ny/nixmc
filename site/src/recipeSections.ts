// Shared metadata for the built-in recipe sections, in the order we surface them.
// Section names must match the `section:` front matter in the app's recipe files.

export interface RecipeSection {
	name: string;
	slug: string;
	icon: string; // lucide-react icon name
	blurb: string;
}

export const RECIPE_SECTIONS: RecipeSection[] = [
	{ name: "macOS Settings", slug: "macos-settings", icon: "SlidersHorizontal", blurb: "Dock, Finder, trackpad, hot corners, screenshots, and other defaults." },
	{ name: "Packages", slug: "packages", icon: "Package", blurb: "CLI kits, dev runtimes, desktop apps, and Homebrew casks." },
	{ name: "Shell & Environment", slug: "shell-environment", icon: "SquareTerminal", blurb: "zsh, prompt, history, direnv, mise, tmux, aliases, and env vars." },
	{ name: "Services", slug: "services", icon: "Server", blurb: "Tailscale, Syncthing, nginx, databases, launchd agents, and more." },
	{ name: "Security & Secrets", slug: "security-secrets", icon: "ShieldCheck", blurb: "Touch ID for sudo, firewall, SOPS, SSH, and commit signing." },
	{ name: "AI Agents", slug: "ai-agents", icon: "Bot", blurb: "Claude Code, Codex, OpenCode, Ollama, and shared MCP setup." },
	{ name: "Fonts", slug: "fonts", icon: "Type", blurb: "Coding, UI, office, Nerd Fonts, CJK/emoji, and handwriting." },
	{ name: "For Programmers", slug: "programmers", icon: "Code2", blurb: "Dev terminal, polyglot toolchains, Emacs daemon, module layout." },
	{ name: "For Designers", slug: "designers", icon: "Palette", blurb: "Design kit, terminal theme, and a window workflow." },
	{ name: "For Writers & Researchers", slug: "writers", icon: "PenLine", blurb: "Daily writing tools, focus defaults, and a research suite." },
	{ name: "For Gamers", slug: "gamers", icon: "Gamepad2", blurb: "Mac gaming, a NixOS gaming box, and remote play." },
	{ name: "For Streamers", slug: "streamers", icon: "Radio", blurb: "Streaming apps, a capture box, and a Linux stream rig." },
	{ name: "For Homelab Admins", slug: "homelab", icon: "HardDrive", blurb: "Ops toolbelt, SSH to the homelab, and a boot tunnel." },
	{ name: "For Laptop Nomads", slug: "nomads", icon: "Plane", blurb: "Travel profile, presentation mode, and replacement-Mac capture." },
	{ name: "For Security-Minded Users", slug: "security", icon: "Lock", blurb: "Harden sudo & firewall, SSH hygiene, and secret recipients." },
];

export function sectionMeta(name: string): RecipeSection | undefined {
	return RECIPE_SECTIONS.find((s) => s.name === name);
}
