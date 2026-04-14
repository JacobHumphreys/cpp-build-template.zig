{
  description = "Flake Dependencies for my C/CPP template for building with Zig. Generated with AI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;

    zigCompileCommands = pkgs.fetchFromGitHub {
      owner = "the-argus";
      repo = "zig-compile-commands";
      rev = "70fb439897e12cae896c071717d7c9c382918689";
      sha256 = "dUtfifueNJkwBvbossc7Eohv6QbH+9vzCiMReghOgu8=";
    };

    dependencies = with pkgs; [
      zig_0_15
      rocmPackages.clang
    ];

    developmentTools = with pkgs; [
      lldb_20
      gdb
    ];
  in {
    devShells.x86_64-linux.default = pkgs.mkShell {
      name = "clang-zig-shell";

      buildInputs = dependencies ++ developmentTools;

      shellHook = ''
        zig build cmds;
        echo "🔧 CPP/C Template.Zig dev shell (Nixpkgs 25.05)";
      '';
    };

    packages.x86_64-linux.default = pkgs.stdenv.mkDerivation {
      pname = "cpp.zig";
      version = "1.0";

      src = ./.;

      buildInputs = dependencies;

      env = {
        HOME = "$PWD";
        ZIG_GLOBAL_CACHE_DIR = "$PWD/.cache";
        ZIG_LOCAL_CACHE_DIR = "$PWD/.zig-cache";
      };

      preBuild = ''
      '';

      buildPhase = ''
        mkdir -p $ZIG_GLOBAL_CACHE_DIR/p/zig_compile_commands-0.0.1-OZg5-ULBAABTh3NXO3WXoSUX1474ez0EouuoT2yDANhz
        cp -r ${zigCompileCommands}/* $ZIG_GLOBAL_CACHE_DIR/p/zig_compile_commands-0.0.1-OZg5-ULBAABTh3NXO3WXoSUX1474ez0EouuoT2yDANhz/

        zig build -Dbuild-static -Dbuild-dynamic;
      '';

      installPhase = ''
        mkdir -p $out/bin
        cp -r $PWD/zig-out/bin/zig-compiled $out/bin/cpp.zig

        mkdir -p $out/lib
        cp -r $PWD/zig-out/lib/* $out/lib/
      '';
    };

    apps.x86_64-linux."cpp.zig" = {
      type = "app";
      program = "${self.packages.x86_64-linux.default}/bin/cpp.zig";
    };
  };
}
