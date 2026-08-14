{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.dockerRegistry;

  blobCache = if cfg.enableRedisCache then "redis" else "inmemory";

  registryConfig = {
    version = "0.1";
    log.fields.service = "registry";
    storage = {
      cache.blobdescriptor = blobCache;
      delete.enabled = cfg.enableDelete;
    }
    // (lib.optionalAttrs (cfg.storagePath != null) {
      filesystem.rootdirectory = cfg.storagePath;
    });
    http = {
      addr = "${cfg.listenAddress}:${toString cfg.port}";
      headers.X-Content-Type-Options = [ "nosniff" ];
    };
    health.storagedriver = {
      enabled = true;
      interval = "10s";
      threshold = 3;
    };
  };

  needsRuntimeConfig = cfg.enableRedisCache && cfg.redisPasswordFile != null;

  staticConfigFile = pkgs.writeText "docker-registry-config.yml" (
    builtins.toJSON (lib.recursiveUpdate registryConfig cfg.extraConfig)
  );

  runtimeConfigPath = "/run/docker-registry/config.yml";

  configFile = if needsRuntimeConfig then runtimeConfigPath else staticConfigFile;

in
{
  options.services.dockerRegistry = {
    enable = lib.mkEnableOption "Docker Registry";

    package = lib.mkPackageOption pkgs "distribution" {
      example = "gitlab-container-registry";
    };

    listenAddress = lib.mkOption {
      description = "Docker registry host or ip to bind to.";
      default = "127.0.0.1";
      type = lib.types.str;
    };

    port = lib.mkOption {
      description = "Docker registry port to bind to.";
      default = 5000;
      type = lib.types.port;
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Opens the port used by the firewall.";
    };

    storagePath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = "/var/lib/docker-registry";
      description = ''
        Docker registry storage path for the filesystem storage backend. Set to
        null to configure another backend via extraConfig.
      '';
    };

    enableDelete = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable delete for manifests and blobs.";
    };

    enableRedisCache = lib.mkEnableOption "redis as blob cache";

    redisUrl = lib.mkOption {
      type = lib.types.str;
      default = "localhost:6379";
      description = "Redis host and port.";
    };

    redisPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing the Redis password.  The file is loaded via
        systemd's LoadCredential mechanism and is never written to the Nix
        store.  Leave as null when no password is required.
      '';
    };

    extraConfig = lib.mkOption {
      description = "Docker extra registry configuration via attribute set.";
      example = lib.literalExpression ''
        {
          log.level = "debug";
        }
      '';
      default = { };
      type = lib.types.attrs;
    };

    configFile = lib.mkOption {
      default = staticConfigFile;
      defaultText = lib.literalExpression ''
        pkgs.writeText "docker-registry-config.yml" "# generated config"
      '';
      description = ''
        Path to CNCF distribution config file.  Overrides extraConfig entirely
        when set.  Note: when redisPasswordFile is set the service generates a
        runtime config under /run/docker-registry/ - this option is ignored in
        that case.
      '';
      type = lib.types.path;
    };

    enableGarbageCollect = lib.mkEnableOption "garbage collect";

    garbageCollectDates = lib.mkOption {
      default = "daily";
      type = lib.types.str;
      description = ''
        Specification (in the format described by
        {manpage}`systemd.time(7)`) of the time at
        which the garbage collect will occur.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.dockerRegistry.extraConfig = lib.mkIf cfg.enableRedisCache {
      redis = {
        addr = "${cfg.redisUrl}";
        password = "${cfg.redisPassword}";
        db = 0;
        dialtimeout = "10ms";
        readtimeout = "10ms";
        writetimeout = "10ms";
        pool = {
          maxidle = 16;
          maxactive = 64;
          idletimeout = "300s";
        };
      };
    };

    systemd.services.docker-registry = {
      description = "Docker Container Registry";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      preStart = lib.mkIf needsRuntimeConfig ''
        set -euo pipefail
        REDIS_PASSWORD=$(cat "$CREDENTIALS_DIRECTORY/redis-password")
        # Merge the static template with the runtime password.
        # jq is used for safe JSON manipulation; it is available in pkgs.jq.
        ${pkgs.jq}/bin/jq \
          --arg pw "$REDIS_PASSWORD" \
          '.redis.password = $pw' \
          ${staticConfigFile} \
          > ${runtimeConfigPath}
        chmod 600 ${runtimeConfigPath}
      '';

      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} serve ${configFile}";
        User = "docker-registry";
        Group = "docker-registry";
        WorkingDirectory = lib.mkIf (cfg.storagePath != null) cfg.storagePath;

        LoadCredential = lib.mkIf (cfg.redisPasswordFile != null) "redis-password:${cfg.redisPasswordFile}";

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ReadWritePaths =
          lib.optional (cfg.storagePath != null) cfg.storagePath
          ++ lib.optional needsRuntimeConfig "/run/docker-registry";

        RuntimeDirectory = "docker-registry";
        RuntimeDirectoryMode = "0750";
        StateDirectory = lib.mkIf (cfg.storagePath == "/var/lib/docker-registry") "docker-registry";

        AmbientCapabilities = lib.mkIf (cfg.port < 1024) [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = if cfg.port < 1024 then [ "CAP_NET_BIND_SERVICE" ] else [ "" ];

        PrivateUsers = !(cfg.port < 1024);

        NoNewPrivileges = true;

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
        RemoveIPC = true;
        LockPersonality = true;

        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ]
        ++ lib.optional cfg.enableRedisCache "AF_UNIX";

        MemoryDenyWriteExecute = true;

        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];

        UMask = "0027";
      };
    };

    systemd.services.docker-registry-garbage-collect = {
      description = "Garbage collection for docker-registry";

      conflicts = [ "docker-registry.service" ];
      before = [ "docker-registry.service" ];

      restartIfChanged = false;
      unitConfig.X-StopOnRemoval = false;

      serviceConfig = {
        Type = "oneshot";
        User = "docker-registry";
        Group = "docker-registry";

        ExecStart = "${cfg.package}/bin/registry garbage-collect --delete-untagged ${configFile}";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ReadWritePaths = lib.optional (cfg.storagePath != null) cfg.storagePath;
        CapabilityBoundingSet = [ "" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
      };

      startAt = lib.optional cfg.enableGarbageCollect cfg.garbageCollectDates;
    };

    users.users.docker-registry =
      (lib.optionalAttrs (cfg.storagePath != null) {
        createHome = true;
        home = cfg.storagePath;
      })
      // {
        group = "docker-registry";
        isSystemUser = true;
      };
    users.groups.docker-registry = { };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
