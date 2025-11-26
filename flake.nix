{
  description = "MTUProtect - Automatically set MTU for broken VPNs like GlobalProtect";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }: 
    let
      supportedSystems = [ "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
    in
    {
      packages = forAllSystems (system: {
        default = nixpkgsFor.${system}.callPackage ./default.nix { };
        mtuprotect = self.packages.${system}.default;
      });

      darwinModules.mtuprotect = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.mtuprotect;
          mtuprotect = self.packages.${pkgs.system}.default;
          daemonArgs = [ "${mtuprotect}/Library/Application Support/MTUProtect/mtuprotect-daemon" ]
            ++ [ (if cfg.autoWatch then "true" else "false") ]
            ++ [ cfg.interface ]
            ++ [ (toString cfg.mtu) ];
        in
        {
          options.services.mtuprotect = {
            enable = mkEnableOption "MTUProtect daemon and menu bar app";

            autoWatch = mkOption {
              type = types.bool;
              default = true;
              description = "Automatically launch the menu bar watcher app when the daemon starts.";
            };

            interface = mkOption {
              type = types.str;
              default = "utun4";
              description = "The VPN interface name (e.g., 'utun4').";
            };

            mtu = mkOption {
              type = types.int;
              default = 1280;
              description = "The MTU value to set for the VPN interface.";
            };
          };

          config = mkIf cfg.enable {
            # Install the app to /Applications
            environment.systemPackages = [ mtuprotect ];

            # Create LaunchDaemon for mtuprotect
            launchd.daemons.mtuprotect = {
              serviceConfig = {
                Label = "il.luminati.mtuprotect";
                ProgramArguments = daemonArgs;
                RunAtLoad = true;
                KeepAlive = true;
                StandardOutPath = "/var/log/mtuprotect.log";
                StandardErrorPath = "/var/log/mtuprotect.log";
              };
            };
          };
        };

      darwinModules.default = self.darwinModules.mtuprotect;
    };
}
