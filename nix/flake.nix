{
  description = "SpeedyBags — WoW bag addon dev environment";

  inputs = {
    pins.url = "path:/home/luna/nix/pins";
    nixpkgs.follows = "pins/nixpkgs";
  };

  outputs =
    inputs@{ self, pins, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Lua 5.1 is not a stylistic choice — it is WoW's actual runtime.
      # Everything here targets 5.1 on purpose; see CLAUDE.md.
      luaTools = with pkgs; [
        lua5_1
        lua51Packages.luacheck
        lua-language-server
        stylua
      ];

      tools = with pkgs; [
        git
        ripgrep
      ];
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = luaTools ++ tools;

        shellHook = ''
          echo "SpeedyBags dev shell"
          echo "  lua:       $(lua5.1 -v 2>&1)"
          echo "  luacheck:  $(luacheck --version 2>&1 | head -1)"
          echo "  lua-ls:    $(lua-language-server --version 2>&1 || echo present)"
          echo "  stylua:    $(stylua --version)"
        '';
      };
    };
}
