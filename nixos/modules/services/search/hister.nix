{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.hister;
  config_file = ''
    app:
        directory: ${cfg.directory}
        search_url: https://google.com/search?q={query}
        log_level: info
        debug_sql: false
    server:
        address: ${cfg.listenAddress}
        base_url: ${cfg.baseUrl}
        database: db.sqlite3
    hotkeys:
        /: focus_search_input
        '?': show_hotkeys
        alt+enter: open_result_in_new_tab
        alt+j: select_next_result
        alt+k: select_previous_result
        alt+o: open_query_in_search_engine
        alt+v: view_result_popup
        enter: open_result
        tab: autocomplete
  '';
in
{
  options.services.hister = {

    enable = lib.mkEnableOption "hister (local browser history search) server";

    package = lib.mkPackageOption pkgs "hister" { };

    listenAddress = lib.mkOption {
      description = "Listening IP:port for the server";
      type = lib.types.str;
      default = "127.0.0.1:4433";
    };

    baseUrl = lib.mkOption {
      description = "Base URL for the server";
      type = lib.types.str;
      default = "";
    };

    directory = lib.mkOption {
      description = "Working directory of the server";
      type = lib.types.str;
      default = "/var/lib/hister";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    environment.etc."hister/hister-server.yml".text = config_file;

    systemd.user.services.hister = {
      description = "Hister (local browser history search) server";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} listen --config /etc/hister/hister-server.yml";
        #User = "hister";
        #Group = "hister";
        UMask = "0077";
        Restart = "always";
        #DynamicUser = true;
        ProtectHome = true;
        PrivateDevices = true;
        ProtectHostname = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = "strict";
        ProtectProc = "invisible";

        LockPersonality = true;
        RestrictRealtime = true;
        RestrictNamespaces = true;
        SystemCallFilter = [ "@system-service" ];

        SystemCallErrorNumber = "EPERM";
        SystemCallArchitectures = "native";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];

        StateDirectory = "hister";
        StateDirectoryMode = "0755";
        ConfigurationDirectory = "hister";
        ConfigurationDirectoryMode = "0755";
      };
    };

    users.users."hister" = {
      name = "hister";
      description = lib.mkDefault "Hister service user";
      isSystemUser = true;
      group = "hister";
      extraGroups = [ "systemd-journal" ];
    };

    users.groups."hister" = lib.mapAttrs (name: lib.mkOptionDefault) { };
  };

  meta = {
    maintainers = with lib.maintainers; [
      gaelj
    ];
  };
}
