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
          cfg = config.programs.mtuprotect;
          mtuprotect = self.packages.${pkgs.system}.default;
        in
        {
          options.programs.mtuprotect = {
            enable = mkEnableOption "MTUProtect daemon and menu bar app";

            vpnInterface = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "The VPN interface name (e.g., 'utun3'). Leave null to configure via the menu bar app.";
            };
          };

          config = mkIf cfg.enable {
            # Install the app to /Applications
            environment.systemPackages = [ mtuprotect ];

            # Create LaunchDaemon for mtuprotect
            launchd.daemons.mtuprotect = {
              serviceConfig = {
                Label = "il.luminati.mtuprotect";
                ProgramArguments = [ "${mtuprotect}/Library/Application Support/MTUProtect/mtuprotect-daemon" ];
                RunAtLoad = true;
                KeepAlive = true;
                StandardOutPath = "/var/log/mtuprotect.log";
                StandardErrorPath = "/var/log/mtuprotect.log";
              };
            };

            # Set VPN interface preference if specified
            system.activationScripts.postActivation.text = mkIf (cfg.vpnInterface != null) ''
              echo "Setting MTUProtect VPN interface to ${cfg.vpnInterface}"
              /usr/bin/defaults write il.luminati.mtuwatch vpnInterface "${cfg.vpnInterface}"
            '';
          };
        };

      darwinModules.default = self.darwinModules.mtuprotect;
    };
}
