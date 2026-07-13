import Foundation

/// A minimal, self-contained nix-darwin + home-manager starter flake, with
/// Homebrew driven from a JSON data file (`builtins.fromJSON`) so brew edits
/// never require parsing Nix. Mirrors the pattern in the nixmc repo's
/// `templates/*/.nixmc/homebrew/`. System and user settings use explicit
/// modules so the initial repository has the same layout nixmc presents.
///
/// NOTE: this is a starting point — review before shipping. Placeholders
/// (@HOSTNAME@, @USERNAME@, @SYSTEM@) are substituted by `ConfigScaffold`.
enum ConfigTemplate {
    /// relative path → file contents (with placeholders)
    static let files: [String: String] = [
        "flake.nix": flake,
        ".nixmc/homebrew/default.nix": homebrewModule,
        ".nixmc/homebrew/data.json": homebrewData,
        "modules/darwin/default.nix": darwinModule,
        "modules/darwin/packages.nix": packagesModule,
        "modules/darwin/fonts.nix": emptyModule,
        "modules/darwin/macos-settings.nix": emptyModule,
        "modules/darwin/services.nix": emptyModule,
        "modules/darwin/security-secrets.nix": emptyModule,
        "modules/home/default.nix": homeModule,
        "modules/home/shell-environment.nix": emptyModule,
        "modules/home/ai-agents.nix": emptyModule,
        "CLAUDE.md": agentGuide,
        ".gitignore": "result\nresult-*\n",
    ]

    private static let flake = """
    {
      description = "nixmc-managed nix-darwin configuration";

      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
        nix-darwin.url = "github:nix-darwin/nix-darwin/master";
        nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
        home-manager.url = "github:nix-community/home-manager";
        home-manager.inputs.nixpkgs.follows = "nixpkgs";
      };

      outputs = { self, nixpkgs, nix-darwin, home-manager }:
        let
          system = "@SYSTEM@";
        in
        {
          darwinConfigurations."@HOSTNAME@" = nix-darwin.lib.darwinSystem {
            inherit system;
            modules = [
              ./.nixmc/homebrew
              ./modules/darwin
              home-manager.darwinModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users."@USERNAME@" = import ./modules/home;
              }
            ];
          };
        };
    }
    """

    private static let homebrewModule = """
    { lib, ... }:
    let
      data = builtins.fromJSON (builtins.readFile ./data.json);
    in
    {
      homebrew = {
        enable = lib.mkDefault true;
        taps = data.taps or [ ];
        brews = data.brews or [ ];
        casks = data.casks or [ ];
      }
      // lib.optionalAttrs (data ? onActivation) {
        onActivation = data.onActivation;
      };
    }
    """

    private static let homebrewData = """
    {
      "taps": [],
      "brews": [],
      "casks": [],
      "onActivation": { "autoUpdate": true, "upgrade": true, "cleanup": "none" }
    }
    """

    private static let darwinModule = """
    { ... }:
    {
      imports = [
        ./packages.nix
        ./fonts.nix
        ./macos-settings.nix
        ./services.nix
        ./security-secrets.nix
      ];

      system.stateVersion = 5;
      system.primaryUser = "@USERNAME@";
      nixpkgs.hostPlatform = "@SYSTEM@";
      # Determinate manages Nix itself.
      nix.enable = false;

      users.users."@USERNAME@".home = "/Users/@USERNAME@";
    }
    """

    private static let packagesModule = """
    { ... }:
    {
      # System-wide Nix packages belong here.
      environment.systemPackages = [ ];
    }
    """

    private static let emptyModule = """
    { ... }:
    {
    }
    """

    private static let homeModule = """
    { ... }:
    {
      imports = [
        ./shell-environment.nix
        ./ai-agents.nix
      ];

      home.stateVersion = "24.05";
    }
    """

    private static let agentGuide = """
    # Agent guide for this nix-darwin config

    You are editing a nix-darwin + home-manager flake managed by nixmc.

    - Homebrew apps: DO NOT edit any `.nix` for these. Add/remove entries in
      `.nixmc/homebrew/data.json` (`taps`, `brews`, `casks`).
    - Each configuration area has a matching module: `modules/darwin/packages.nix`,
      `fonts.nix`, `macos-settings.nix`, `services.nix`, or `security-secrets.nix`;
      and `modules/home/shell-environment.nix` or `ai-agents.nix` for user settings.
    - After editing, the app runs `darwin-rebuild build` to validate. Keep changes
      minimal and formatted. If the build fails, read the error and fix it.
    """
}
