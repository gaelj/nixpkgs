{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.openTerminal;

  # OPEN_TERMINAL_MULTI_USER is enabled if cfg.multiUser is true OR if the
  # user explicitly set OPEN_TERMINAL_MULTI_USER in cfg.environment to anything
  # other than false/0/no/"".
  multiUserEnabled =
    cfg.multiUser
    || (
      let
        value = lib.toLower (cfg.environment.OPEN_TERMINAL_MULTI_USER or "");
      in
      value != "" && value != "false" && value != "0" && value != "no"
    );
in
{
  options.services.openTerminal = {
    enable = lib.mkEnableOption "the open-terminal Open WebUI terminal server";

    package = lib.mkPackageOption pkgs "open-terminal" { };

    host = lib.mkOption {
      type = lib.types.str;
      default = "[IP_ADDRESS]";
      description = ''
        Address the server binds to, passed to `--host`. Defaults to
        `[IP_ADDRESS]` (all network interfaces), matching upstream. Set to
        `[IP_ADDRESS]` to restrict access to this machine.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Port the server listens on";
    };

    multiUser = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable multi-user isolation (sets `OPEN_TERMINAL_MULTI_USER = "true"`).
        When enabled, each distinct `X-User-Id` header from Open WebUI is mapped
        to a dedicated Linux user account provisioned via `useradd`.

        Note: Multi-user mode requires running the service as root (DynamicUser
        is disabled) so it can provision accounts, create home directories,
        and run user commands via `sudo -u`.
      '';
    };

    corsAllowedOrigins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "*" ];
      description = ''
        Allowed CORS origins, passed to `--cors-allowed-origins` as a
        comma-separated list. Defaults to `[ "*" ]` (all origins), matching
        upstream. The server ships no UI of its own, so restrict this when
        only the Open WebUI backend will call it through its proxy.
      '';
    };

    openFirewall = lib.mkEnableOption "open the server port in the firewall";

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Attribute set of additional environment variables, such as:
          - OPEN_TERMINAL_USER_PREFIX
          - OPEN_TERMINAL_INFO
          - OPEN_TERMINAL_SYSTEM_PROMPT
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to an EnvironmentFile providing OPEN_TERMINAL_API_KEY.
        If not set, the server generates and logs a key on startup.
        If no key is ever provided, the API is exposed without authentication.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra CLI arguments passed to `open-terminal run`";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optionals multiUserEnabled [
      "services.openTerminal: multi-user mode is enabled; the service runs as root (DynamicUser disabled) because it provisions OS users via useradd/chown/sudo."
    ];

    systemd.services.open-terminal = {
      description = "open-terminal Open WebUI terminal server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # Multi-user mode provisions accounts with `useradd -m -s /bin/bash`,
      # fixes permissions with `chown`/`chmod`, and switches users with `sudo -u`.
      # Include them in the service PATH alongside /run/wrappers/bin for setuid sudo.
      path = lib.optionals multiUserEnabled [
        pkgs.shadow
        pkgs.coreutils
        pkgs.bash
        pkgs.util-linux
        "/run/wrappers"
      ];

      environment =
        cfg.environment
        // (lib.optionalAttrs cfg.multiUser {
          OPEN_TERMINAL_MULTI_USER = "true";
        });

      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} run --host ${cfg.host} --port ${toString cfg.port} ${
          lib.concatStringsSep " " (
            cfg.extraArgs
            ++ lib.optionals (cfg.corsAllowedOrigins != [ ]) [
              "--cors-allowed-origins ${lib.concatStringsSep "," cfg.corsAllowedOrigins}"
            ]
          )
        }";
        Restart = "on-failure";
        RestartSec = 5;
        DynamicUser = !multiUserEnabled;
        # The server serves files from its working directory
        StateDirectory = "open-terminal";
        StateDirectoryMode = "0750";
        WorkingDirectory = "%S/open-terminal";
      }
      // (lib.optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      });
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [
        cfg.port
      ];
    };
  };

  meta.maintainers = with lib.maintainers; [ gaelj ];
}
