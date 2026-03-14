{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.networking.isponsorblocktv;
in
{
  options.services.networking.isponsorblocktv = {
    enable = lib.mkEnableOption "isponsorblocktv";

    package = lib.mkPackageOption pkgs "isponsorblocktv" { };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      # Run this to (re)configure: isponsorblocktv-setup
      (pkgs.writeShellScriptBin "isponsorblocktv-setup" ''
        exec ${lib.getExe' pkgs.systemd "systemd-run"} \
          --pty \
          --wait \
          --unit=isponsorblocktv-setup \
          --description="iSponsorBlockTV CLI configurator" \
          --property=User=isponsorblocktv \
          --property=Group=isponsorblocktv \
          --property=WorkingDirectory=/var/lib/isponsorblocktv \
          --property=StateDirectory=isponsorblocktv \
          --property=StateDirectoryMode=0700 \
          --property=ReadWritePaths=/var/lib/isponsorblocktv \
          --property=ProtectSystem=strict \
          --property=ProtectHome=yes \
          --property=PrivateTmp=yes \
          --property=PrivateDevices=yes \
          --property=NoNewPrivileges=yes \
          --property=CapabilityBoundingSet= \
          --property=AmbientCapabilities= \
          --property=SystemCallFilter=@system-service \
          --property=SystemCallArchitectures=native \
          --property=ProtectKernelTunables=yes \
          --property=ProtectKernelModules=yes \
          --property=ProtectKernelLogs=yes \
          --property=ProtectClock=yes \
          --property=ProtectControlGroups=yes \
          --property=RestrictNamespaces=yes \
          --property=LockPersonality=yes \
          --property=MemoryDenyWriteExecute=yes \
          --property=RestrictRealtime=yes \
          --property=RestrictSUIDSGID=yes \
          --property=RemoveIPC=yes \
          --property=UMask=0066 \
          --property=RestrictAddressFamilies=AF_INET \
          --property=RestrictAddressFamilies=AF_INET6 \
          --property=Conflicts=isponsorblocktv.service \
          -- \
          ${lib.getExe cfg.package} --setup --data /var/lib/isponsorblocktv
      '')
    ];

    users.users.isponsorblocktv = {
      isSystemUser = true;
      group = "isponsorblocktv";
      description = "iSponsorBlockTV service account";
    };

    users.groups.isponsorblocktv = { };

    systemd.services.isponsorblocktv = {
      description = "iSponsorBlockTV - SponsorBlock client for YouTube TV";
      documentation = [ "https://github.com/dmunozv04/iSponsorBlockTV" ];

      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      # Don't start if config.json hasn't been generated yet
      unitConfig.ConditionPathExists = "/var/lib/isponsorblocktv/config.json";

      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} --data /var/lib/isponsorblocktv";
        WorkingDirectory = "/var/lib/isponsorblocktv";

        User = "isponsorblocktv";
        Group = "isponsorblocktv";

        StateDirectory = "isponsorblocktv"; # /var/lib/isponsorblocktv
        StateDirectoryMode = "0700";
        RuntimeDirectory = "isponsorblocktv"; # /run/isponsorblocktv
        RuntimeDirectoryMode = "0700";

        Restart = "always";
        RestartSec = "10s";
        StartLimitBurst = 5;
        StartLimitIntervalSec = "120s";

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ReadWritePaths = [ "/var/lib/isponsorblocktv" ];

        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";

        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@raw-io"
          "~@reboot"
          "~@swap"
          "~@obsolete"
        ];
        SystemCallArchitectures = "native";

        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        UMask = "0066";

        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
  };

  meta.maintainers = with lib.maintainers; [ gaelj ];
}
