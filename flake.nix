{
  description = "MerrinxUI Layer Hop - World of Warcraft: Forever addon";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ace3 = {
      url = "github:WoWUIDev/Ace3";
      flake = false;
    };

    wow-api = {
      url = "github:Ketho/vscode-wow-api";
      flake = false;
    };
  };

  outputs =
    inputs@{ nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        { system, lib, ... }:
        let
          pkgs = import nixpkgs { inherit system; };

          pre-commit-check = inputs.git-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              statix.enable = true;
              deadnix.enable = true;
              nil.enable = true;
              nixfmt.enable = true;
              luacheck = {
                enable = true;
                package = pkgs.lua51Packages.luacheck;
              };
              stylua.enable = true;
            };
          };

          addonLibs = pkgs.runCommand "merrinxui-layerhop-libs" { } ''
            mkdir -p $out
            for d in LibStub CallbackHandler-1.0 AceAddon-3.0 AceConsole-3.0 AceEvent-3.0 AceDB-3.0 AceGUI-3.0 AceConfig-3.0; do
              cp -r ${inputs.ace3}/$d $out/$d
            done
            cp ${inputs.ace3}/LICENSE.txt $out/Ace3-LICENSE.txt
          '';

          luarc = pkgs.writeText "luarc.json" (
            builtins.toJSON {
              runtime.version = "Lua 5.1";
              workspace = {
                library = [
                  "${inputs.wow-api}/Annotations/Core"
                  "${addonLibs}"
                ];
                checkThirdParty = false;
              };
            }
          );

          merrinxui-layerhop = pkgs.runCommand "merrinxui-layerhop" { } ''
            mkdir -p "$out/MerrinxUI_LayerHop"
            cp -r ${./MerrinxUI_LayerHop}/. "$out/MerrinxUI_LayerHop"/
            cp -r ${addonLibs} "$out/MerrinxUI_LayerHop/Libs"
            chmod -R u+w "$out/MerrinxUI_LayerHop"

            toc="$out/MerrinxUI_LayerHop/MerrinxUI_LayerHop.toc"
            while IFS= read -r raw || [ -n "$raw" ]; do
              line=$(printf '%s' "$raw" | tr -d '\r')
              line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
              case "$line" in
                "" | "#"*) continue ;;
              esac
              rel=$(printf '%s' "$line" | tr '\\' '/')
              if [ ! -e "$out/MerrinxUI_LayerHop/$rel" ]; then
                echo "missing: $rel"
                exit 1
              fi
            done < "$toc"

            embeds="$out/MerrinxUI_LayerHop/embeds.xml"
            while IFS= read -r ref || [ -n "$ref" ]; do
              rel=$(printf '%s' "$ref" | tr '\\' '/')
              if [ ! -e "$out/MerrinxUI_LayerHop/$rel" ]; then
                echo "missing: $rel"
                exit 1
              fi
            done < <(grep -o 'file="[^"]*"' "$embeds" | sed 's/^file="//; s/"$//')
          '';

          lua-syntax =
            pkgs.runCommand "merrinxui-layerhop-lua-syntax" { nativeBuildInputs = [ pkgs.lua5_1 ]; }
              ''
                find ${./MerrinxUI_LayerHop} -name '*.lua' -exec luac -p {} +
                touch "$out"
              '';

          busted =
            let
              source = lib.fileset.toSource {
                root = ./.;
                fileset = lib.fileset.unions [
                  ./MerrinxUI_LayerHop
                  ./spec
                ];
              };
            in
            pkgs.runCommand "merrinxui-layerhop-busted"
              {
                nativeBuildInputs = [
                  pkgs.lua5_1
                  pkgs.lua51Packages.busted
                ];
              }
              ''
                export HOME="$TMPDIR"
                cd ${source}
                busted spec
                touch "$out"
              '';

          release = pkgs.runCommand "merrinxui-layerhop-release" { nativeBuildInputs = [ pkgs.zip ]; } ''
            cp -r ${merrinxui-layerhop}/MerrinxUI_LayerHop .
            chmod -R u+w MerrinxUI_LayerHop
            find MerrinxUI_LayerHop -exec touch -h -d '1980-01-02T00:00:00Z' {} +
            mkdir -p $out
            find MerrinxUI_LayerHop -type f | LC_ALL=C sort | zip -X -D -@ $out/MerrinxUI_LayerHop.zip
          '';
        in
        {
          formatter = pkgs.nixfmt;

          packages = {
            inherit merrinxui-layerhop release;
            default = merrinxui-layerhop;
          };

          checks = {
            inherit
              pre-commit-check
              merrinxui-layerhop
              lua-syntax
              busted
              ;
          };

          devShells.default = pkgs.mkShell {
            shellHook = pre-commit-check.shellHook + "\ninstall -m 644 ${luarc} .luarc.json\n";
            packages =
              pre-commit-check.enabledPackages
              ++ (with pkgs; [
                lua5_1
                lua51Packages.luacheck
                lua51Packages.busted
                stylua
                lua-language-server
                zip
                unzip
              ]);
          };
        };
    };
}
