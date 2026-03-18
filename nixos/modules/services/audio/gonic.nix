{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.gonic;
  settingsFormat = pkgs.formats.keyValue {
    mkKeyValue = lib.generators.mkKeyValueDefault { } " ";
    listsAsDuplicateKeys = true;
  };
  assertKey = key: {
    assertion = cfg.settings ? ${key};
    message = "Please set services.gonic.settings.${key}. See https://github.com/sentriz/gonic#configuration-options for supported values.";
  };
in
{
  options = {
    services.gonic = {

      enable = lib.mkEnableOption "Gonic music server";

      package = lib.mkPackageOption pkgs "gonic" { };

      settings = lib.mkOption rec {
        type = settingsFormat.type;
        apply = lib.recursiveUpdate default;
        default = {
          listen-addr = "127.0.0.1:4747";
          cache-path = "/var/cache/gonic";
          tls-cert = null;
          tls-key = null;
        };
        example = {
          music-path = [ "/mnt/music" ];
          podcast-path = "/mnt/podcasts";
          playlists-path = "/mnt/playlists";
        };
        description = ''
          Configuration for Gonic, see <https://github.com/sentriz/gonic#configuration-options> for supported values.
        '';
      };

    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (assertKey "music-path")
      (assertKey "podcast-path")
      (assertKey "playlists-path")
    ];

    users.users.gonic = {
      isSystemUser = true;
      group = "gonic";
      description = "Gonic music server daemon user";
    };

    users.groups.gonic = {};

    systemd.services.gonic = {
      description = "Gonic Media Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart =
          let
            # these values are null by default but should not appear in the final config
            filteredSettings = lib.filterAttrs (
              n: v: !((n == "tls-cert" || n == "tls-key") && v == null)
            ) cfg.settings;
          in
          "${lib.getExe cfg.package} -config-path ${settingsFormat.generate "gonic" filteredSettings}";

        User = "gonic";
        Group = "gonic";
        StateDirectory = "gonic";
        CacheDirectory = "gonic";
        WorkingDirectory = "/var/lib/gonic";
        RuntimeDirectory = "gonic";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";

        RootDirectory = "/run/gonic";
        MountAPIVFS = true;
        ReadWritePaths = "";
        BindPaths = [
          cfg.settings.playlists-path
          cfg.settings.podcast-path
          cfg.settings.cache-path
        ];
        BindReadOnlyPaths = [
          # gonic can access scrobbling services
          "-/etc/resolv.conf"
          "-/etc/hosts"
          "${config.security.pki.caBundle}:/etc/ssl/certs/ca-certificates.crt"
          builtins.storeDir
        ]
        ++ cfg.settings.music-path
        ++ lib.optional (cfg.settings.tls-cert != null) cfg.settings.tls-cert
        ++ lib.optional (cfg.settings.tls-key != null) cfg.settings.tls-key;

        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];

        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        NoNewPrivileges = true;

        PrivateDevices = true;
        PrivateIPC = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        ProtectSystem = "strict";

        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
          "~@mount"
        ];
        SystemCallErrorNumber = "EPERM";

        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RemoveIPC = true;
      };
    };
  };

  meta.maintainers = [ lib.maintainers.autrimpo ];
}
