{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.services.airsonic;
  opt = options.services.airsonic;
in
{
  options = {

    services.airsonic = {
      enable = lib.mkEnableOption "Airsonic, the Free and Open Source media streaming server (fork of Subsonic and Libresonic)";

      user = lib.mkOption {
        type = lib.types.str;
        default = "airsonic";
        description = "User account under which airsonic runs.";
      };

      home = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/airsonic";
        description = ''
          The directory where Airsonic will create files.
          Make sure it is writable.
        '';
      };

      virtualHost = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Name of the nginx virtualhost to use and setup. If null, do not setup any virtualhost.
        '';
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          The host name or IP address on which to bind Airsonic.
          The default value is appropriate for first launch, when the
          default credentials are easy to guess. It is also appropriate
          if you intend to use the virtualhost option in the service
          module. In other cases, you may want to change this to a
          specific IP or 0.0.0.0 to listen on all interfaces.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 4040;
        description = ''
          The port on which Airsonic will listen for
          incoming HTTP traffic. Set to 0 to disable.
        '';
      };

      contextPath = lib.mkOption {
        type = lib.types.path;
        default = "/";
        description = ''
          The context path, i.e., the last part of the Airsonic
          URL. Typically '/' or '/airsonic'. Default '/'
        '';
      };

      maxMemory = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = ''
          The memory limit (max Java heap size) in megabytes.
          Default: 100
        '';
      };

      transcoders = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ "${pkgs.ffmpeg.bin}/bin/ffmpeg" ];
        defaultText = lib.literalExpression ''[ "''${pkgs.ffmpeg.bin}/bin/ffmpeg" ]'';
        description = ''
          List of paths to transcoder executables that should be accessible
          from Airsonic. Symlinks will be created to each executable inside
          ''${config.${opt.home}}/transcoders.
        '';
      };

      jre = lib.mkPackageOption pkgs "jre8" {
        extraDescription = ''
          ::: {.note}
          Airsonic only supports Java 8, airsonic-advanced requires at least
          Java 11.
          :::
        '';
      };

      war = lib.mkOption {
        type = lib.types.path;
        default = "${pkgs.airsonic}/webapps/airsonic.war";
        defaultText = lib.literalExpression ''"''${pkgs.airsonic}/webapps/airsonic.war"'';
        description = "Airsonic war file to use.";
      };

      jvmOptions = lib.mkOption {
        description = ''
          Extra command line options for the JVM running AirSonic.
          Useful for sending jukebox output to non-default alsa
          devices.
        '';
        default = [
        ];
        type = lib.types.listOf lib.types.str;
        example = [
          "-Djavax.sound.sampled.Clip='#CODEC [plughw:1,0]'"
          "-Djavax.sound.sampled.Port='#Port CODEC [hw:1]'"
          "-Djavax.sound.sampled.SourceDataLine='#CODEC [plughw:1,0]'"
          "-Djavax.sound.sampled.TargetDataLine='#CODEC [plughw:1,0]'"
        ];
      };

    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.airsonic = {
      description = "Airsonic Media Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        # Install transcoders.
        ExecStartPre = [
          "${lib.getExe' pkgs.coreutils "rm"} -rf '${cfg.home}/transcode'"
          "${lib.getExe' pkgs.coreutils "mkdir"} -p '${cfg.home}/transcode'"
        ]
        ++ map (
          exe: "${lib.getExe' pkgs.coreutils "ln"} -sf '${exe}' '${cfg.home}/transcode'"
        ) cfg.transcoders;
        ExecStart = ''
          ${cfg.jre}/bin/java -Xmx${toString cfg.maxMemory}m \
          -Dairsonic.home=${cfg.home} \
          -Dserver.address=${cfg.listenAddress} \
          -Dserver.port=${toString cfg.port} \
          -Dserver.context-path=${cfg.contextPath} \
          -Djava.awt.headless=true \
          ${lib.optionalString (cfg.virtualHost != null) "-Dserver.use-forward-headers=true"} \
          ${toString cfg.jvmOptions} \
          -verbose:gc \
          -jar ${cfg.war}
        '';
        Restart = "always";
        User = "airsonic";
        UMask = "0022";

        NoNewPrivileges = true;
        AmbientCapabilities = [ "" ];
        CapabilityBoundingSet = [ "" ];
        # The music directories and the home are configured by the user and
        # are frequently placed under /home, so neither the filesystem nor
        # the home directories may be locked down further than this;
        # PrivateDevices is left off because the jukebox feature plays
        # through ALSA devices, ProtectProc/ProcSubset because the JVM's
        # container support reads /proc/1/cgroup, and
        # MemoryDenyWriteExecute because the JVM is a JIT compiler.
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.home ];
        PrivateTmp = true;
        PrivateIPC = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RemoveIPC = true;
        SystemCallArchitectures = "native";
        # Only the base filter set: the ~@privileged/~@resources exclusions
        # would deny ioctls and scheduling calls the JVM and the ALSA jukebox
        # path legitimately need, and unknown calls fail with EPERM instead of
        # killing the service.
        SystemCallFilter = [ "@system-service" ];
        SystemCallErrorNumber = "EPERM";
        # AF_NETLINK for getifaddrs() when enumerating the listen address.
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
          "AF_NETLINK"
        ];
      };
    };

    services.nginx = lib.mkIf (cfg.virtualHost != null) {
      enable = true;
      recommendedProxySettings = true;
      virtualHosts.${cfg.virtualHost} = {
        locations.${cfg.contextPath}.proxyPass = "http://${cfg.listenAddress}:${toString cfg.port}";
      };
    };

    users.users.airsonic = {
      description = "Airsonic service user";
      group = "airsonic";
      name = cfg.user;
      home = cfg.home;
      createHome = true;
      isSystemUser = true;
    };
    users.groups.airsonic = { };
  };
}
