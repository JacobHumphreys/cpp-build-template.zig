{
  description = "Flake Dependencies for my C/CPP template for building with Zig. Generated with AI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in {
        devShells.default = pkgs.mkShell {
          name = "clang-zig-shell";

          buildInputs = with pkgs; [
            clang
            zig
            pkg-config
            gdb
          ];

          shellHook = ''
            echo "🔧 CPP/C Template.Zig dev shell (Nixpkgs 25.05)"
          '';
        };
      }
    );
}

