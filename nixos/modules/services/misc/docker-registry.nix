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
    // (lib.optionalAttrs (cfg.storagePath != null) { filesystem.rootdirectory = cfg.storagePath; });
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

  configFile = cfg.configFile;

  needsRuntimeConfig = cfg.enableRedisCache && cfg.redisPasswordFile != null;

  runtimeConfigPath = "/run/docker-registry/config.yml";

  # The config file handed to the processes: when a Redis password file is
  # configured the store-reachable config is copied at runtime and the
  # password injected, so the secret never ends up in the Nix store.
  effectiveConfigFile = if needsRuntimeConfig then runtimeConfigPath else configFile;

  generateRuntimeConfig = pkgs.writeShellScript "docker-registry-generate-config" ''
    mkdir -p /run/docker-registry
    ${pkgs.jq}/bin/jq \
      --arg pw "$(cat "$CREDENTIALS_DIRECTORY/redis-password")" \
      '.redis.password = $pw' \
      ${configFile} > ${runtimeConfigPath}
    chown docker-registry:docker-registry ${runtimeConfigPath}
    chmod 0600 ${runtimeConfigPath}
  '';
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
      description = "Set redis host and port.";
    };

    redisPassword = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Set redis password.";
    };

    redisPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "/run/secrets/redis-password";
      description = ''
        Path to a file containing the Redis password, loaded into the service
        with systemd's `LoadCredential=`.  Unlike [](#opt-services.dockerRegistry.redisPassword)
        this keeps the secret out of the Nix store: the effective
        configuration is generated at startup by injecting the password into
        [](#opt-services.dockerRegistry.configFile).  Mutually exclusive with
        [](#opt-services.dockerRegistry.redisPassword) and only used when
        [](#opt-services.dockerRegistry.enableRedisCache) is set.
      '';
    };

    extraConfig = lib.mkOption {
      description = ''
        Docker extra registry configuration.
      '';
      example = lib.literalExpression ''
        {
          log.level = "debug";
        }
      '';
      default = { };
      type = lib.types.attrs;
    };

    configFile = lib.mkOption {
      default = pkgs.writeText "docker-registry-config.yml" (
        builtins.toJSON (lib.recursiveUpdate registryConfig cfg.extraConfig)
      );
      defaultText = lib.literalExpression ''pkgs.writeText "docker-registry-config.yml" "# my custom docker-registry-config.yml ..."'';
      description = ''
        Path to CNCF distribution config file.

        Setting this option will override any configuration applied by the extraConfig option.

        When [](#opt-services.dockerRegistry.redisPasswordFile) is in effect the file is
        read at startup and the password injected with `jq`, so it must be
        JSON (the generated default is).
      '';
      type = lib.types.path;
    };

    enableGarbageCollect = lib.mkEnableOption "garbage collect";

    gcDeleteUntagged = lib.mkEnableOption ''
      deletion of untagged manifests during garbage collection.
      This passes `--delete-untagged` to `registry garbage-collect`, which
      removes blobs reachable only through untagged manifests.
    '';

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
    assertions = [
      {
        assertion = !(cfg.enableRedisCache && cfg.redisPassword != "" && cfg.redisPasswordFile != null);
        message = "At most one of services.dockerRegistry.redisPassword and services.dockerRegistry.redisPasswordFile may be set.";
      }
    ];

    services.dockerRegistry.extraConfig = lib.mkIf cfg.enableRedisCache {
      redis = {
        addr = "${cfg.redisUrl}";
        db = 0;
        dialtimeout = "10ms";
        readtimeout = "10ms";
        writetimeout = "10ms";
        pool = {
          maxidle = 16;
          maxactive = 64;
          idletimeout = "300s";
        };
      }
      // lib.optionalAttrs (cfg.redisPasswordFile == null) {
        password = "${cfg.redisPassword}";
      };
    };

    systemd.services.docker-registry = {
      description = "Docker Container Registry";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} serve ${effectiveConfigFile}";
        User = "docker-registry";
        Group = "docker-registry";
        WorkingDirectory = lib.mkIf (cfg.storagePath != null) cfg.storagePath;

        LoadCredential = lib.mkIf (cfg.redisPasswordFile != null) [
          "redis-password:${cfg.redisPasswordFile}"
        ];
        # Runs as root before dropping to the service user, once the runtime
        # directory exists, so the password-injected config can be handed over
        # owned by (and only readable to) the service user.
        ExecStartPre = lib.mkIf needsRuntimeConfig [ "+${generateRuntimeConfig}" ];

        RuntimeDirectory = "docker-registry";
        RuntimeDirectoryMode = "0750";
        StateDirectory = lib.mkIf (cfg.storagePath == "/var/lib/docker-registry") "docker-registry";
        ReadWritePaths =
          lib.optional (cfg.storagePath != null) cfg.storagePath
          ++ lib.optional needsRuntimeConfig "/run/docker-registry";

        # CAP_NET_BIND_SERVICE is only effective in the host network namespace;
        # inside a private user namespace the capability does not permit binding
        # low ports, so the two are mutually exclusive.
        PrivateUsers = !(cfg.port < 1024);
        AmbientCapabilities = lib.mkIf (cfg.port < 1024) [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = if cfg.port < 1024 then [ "CAP_NET_BIND_SERVICE" ] else [ "" ];

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateIPC = true;
        RemoveIPC = true;
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
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          # communicating with the journal
          "AF_UNIX"
        ];
        # Group-readable uploads allow backup tooling to join the
        # docker-registry group instead of requiring root.
        UMask = "0027";
      };
    };

    systemd.services.docker-registry-garbage-collect = {
      description = "Run Garbage Collection for docker registry";

      restartIfChanged = false;
      unitConfig.X-StopOnRemoval = false;

      serviceConfig = {
        Type = "oneshot";
        LoadCredential = lib.mkIf (cfg.redisPasswordFile != null) [
          "redis-password:${cfg.redisPasswordFile}"
        ];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateIPC = true;
        ReadWritePaths =
          lib.optional (cfg.storagePath != null) cfg.storagePath
          ++ lib.optional needsRuntimeConfig "/run/docker-registry";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        CapabilityBoundingSet = [ "" ];
        AmbientCapabilities = [ "" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RemoveIPC = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        RestrictAddressFamilies = [
          "AF_UNIX"
        ]
        ++ lib.optionals cfg.enableRedisCache [
          "AF_INET"
          "AF_INET6"
        ];
        UMask = "0027";
      };

      # The unit runs as root: the registry must be stopped for the duration of
      # the collection (upstream recommends exclusive access) and restarted
      # afterwards, which a sandboxed service user could not do itself.
      script = ''
        systemctl stop docker-registry.service
        ${lib.optionalString needsRuntimeConfig "${generateRuntimeConfig}\n"}${cfg.package}/bin/registry garbage-collect ${lib.optionalString cfg.gcDeleteUntagged "--delete-untagged"} ${effectiveConfigFile}
        systemctl start docker-registry.service
      '';

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
