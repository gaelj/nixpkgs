{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.airsonic-refix;
in
{
  options.services.airsonic-refix = {
    enable = lib.mkEnableOption "Modern web UI for Subsonic compatible servers";

    package = lib.mkPackageOption pkgs "airsonic-refix" { };

    serverUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The backend Subsonic-compatible server URL.
        When set, the server input on the login page will not be displayed.
      '';
      example = "https://navidrome.example.com";
    };

    virtualHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Name of the nginx virtualhost to use and setup. If null, do not setup any virtualhost.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.nginx = lib.mkIf (cfg.virtualHost != null) {
      enable = true;
      virtualHosts.${cfg.virtualHost} = {
        locations."/" = {
          root = "${cfg.package}/share/airsonic-refix";
          tryFiles = "$uri /index.html";
        };

        # env.js sets window.SERVER_URL
        locations."= /env.js" = {
          extraConfig =
            let
              envJs =
                if cfg.serverUrl != null then
                  ''
                    window.env = {
                      SERVER_URL: "${cfg.serverUrl}",
                    };
                  ''
                else
                  ''
                    window.env = {};
                  '';
            in
            ''
              add_header Content-Type application/javascript;
              return 200 '${envJs}';
            '';
        };
      };
    };
  };
}
