{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.silverbullet;
  defaultUser = "silverbullet";
  defaultGroup = defaultUser;
  defaultSpaceDir = "/var/lib/silverbullet";
in
{
  options = {
    services.silverbullet = {
      enable = lib.mkEnableOption "Silverbullet, an open-source, self-hosted, offline-capable Personal Knowledge Management (PKM) web application";

      package = lib.mkPackageOption pkgs "silverbullet" { };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open port in the firewall.";
      };

      listenPort = lib.mkOption {
        type = lib.types.port;
        default = 3000;
        description = "Port to listen on.";
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Address or hostname to listen on. Defaults to 127.0.0.1.";
      };

      spaceDir = lib.mkOption {
        type = lib.types.path;
        default = defaultSpaceDir;
        example = "/home/yourUser/silverbullet";
        description = ''
          Folder to store Silverbullet's space/workspace.
          By default it is located at `${defaultSpaceDir}`.
        '';
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = defaultUser;
        example = "yourUser";
        description = ''
          The user to run Silverbullet as.
          By default, a user named `${defaultUser}` will be created whose space
          directory is [spaceDir](#opt-services.silverbullet.spaceDir).
        '';
      };

      group = lib.mkOption {
        type = lib.types.str;
        default = defaultGroup;
        example = "yourGroup";
        description = ''
          The group to run Silverbullet under.
          By default, a group named `${defaultGroup}` will be created.
        '';
      };

      envFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/etc/silverbullet.env";
        description = ''
          File containing extra environment variables. For example:

          ```
          SB_USER=user:password
          SB_AUTH_TOKEN=abcdefg12345
          ```
        '';
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "--single" ];
        description = "Extra arguments passed to silverbullet.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.silverbullet = {
      description = "Silverbullet service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "${cfg.user}";
        Group = "${cfg.group}";
        EnvironmentFile = lib.mkIf (cfg.envFile != null) "${cfg.envFile}";
        StateDirectory = lib.mkIf (lib.hasPrefix "/var/lib/" cfg.spaceDir) (
          lib.last (lib.splitString "/" cfg.spaceDir)
        );
        ExecStartPre = lib.mkIf (
          !lib.hasPrefix "/var/lib/" cfg.spaceDir
        ) "${lib.getExe' pkgs.coreutils "mkdir"} -p '${cfg.spaceDir}'";
        ExecStart =
          "${lib.getExe cfg.package} --port ${toString cfg.listenPort} --hostname '${cfg.listenAddress}' '${cfg.spaceDir}' "
          + lib.concatStringsSep " " cfg.extraArgs;
        Restart = "on-failure";
        # Hardening. MemoryDenyWriteExecute is deliberately not set:
        # Silverbullet runs on Deno, and V8 needs writable executable
        # memory for its JIT.
        NoNewPrivileges = true;
        AmbientCapabilities = [ "" ];
        CapabilityBoundingSet = [ "" ];
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateIPC = true;
        ProtectHome = "read-only";
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RemoveIPC = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        SystemCallErrorNumber = "EPERM";
        # AF_UNIX is needed to talk to the journal; the server binds
        # INET/INET6 sockets for its HTTP interface.
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        UMask = "0077";
        # The space directory may live anywhere the user chooses
        # (including under /home, hence ProtectHome=read-only rather
        # than a tmpfs).
        ReadWritePaths = [ cfg.spaceDir ];
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.listenPort ];
    };

    users.users.${defaultUser} = lib.mkIf (cfg.user == defaultUser) {
      isSystemUser = true;
      group = cfg.group;
      description = "Silverbullet daemon user";
    };

    users.groups.${defaultGroup} = lib.mkIf (cfg.group == defaultGroup) { };
  };

  meta.maintainers = with lib.maintainers; [ aorith ];
}
