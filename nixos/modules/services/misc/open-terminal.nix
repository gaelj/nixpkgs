{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.openTerminal;
in
{
  options.services.openTerminal = {
    enable = mkEnableOption "the open-terminal Open WebUI terminal server";

    port = mkOption {
      type = types.port;
      description = "Port opened by the server";
      default = 8000;
    };

    openFirewall = mkEnableOption "open the server port in the firewall";

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Attribute set of additional environment variables, such as:
          - OPEN_TERMINAL_MULTI_USER
          - OPEN_TERMINAL_INFO
          - OPEN_TERMINAL_SYSTEM_PROMPT
      '';
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to an EnvironmentFile providing OPEN_TERMINAL_API_KEY.
        If not set, the server generates and logs a key on startup.
      '';
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra CLI arguments passed to `open-terminal run`";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.open-terminal = {
      description = "open-terminal Open WebUI terminal server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = cfg.environment;

      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.open-terminal} run --host 0.0.0.0 --port ${toString cfg.port} ${lib.concatStringsSep " " cfg.extraArgs}";
        Restart = "on-failure";
        RestartSec = 5;
        DynamicUser = true;
        # The server serves files from its working directory
        StateDirectory = "open-terminal";
        StateDirectoryMode = "0750";
        WorkingDirectory = "%S/open-terminal";
      }
      // (optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      });
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [
        cfg.port
      ];
      allowedUDPPorts = [
        cfg.port
      ];
    };
  };
}
