{
  description = "Flake Dependencies for my C/CPP template for building with Zig. Generated with AI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }: let
    pkgs = import nixpkgs;
    dependencies = with pkgs; [
      rocmPackages.clang
      lldb_20
      zig_0_15
      pkg-config
      gdb
    ];
  in {
    devShells.x86_64-linux.default = pkgs.mkShell {
      name = "clang-zig-shell";

      buildInputs = dependencies;

      shellHook = ''
        echo "🔧 CPP/C Template.Zig dev shell (Nixpkgs 25.05)"
      '';
    };

    # packages.x86_64-linux.default = 
  };
}
