{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.twofauth;

  inherit (lib)
    mkEnableOption
    mkOption
    mkPackageOption
    mkIf
    mkDefault
    mkMerge
    mkAfter
    types
    literalExpression
    ;

  # The package is built with dataDir baked in via symlinks.
  # Override it here so the store path matches the configured stateDir.
  package = cfg.package.override { dataDir = cfg.stateDir; };

  appDir = "${package}/share/2fauth";

  phpPackage = cfg.phpPackage.withExtensions (
    { enabled, all }:
    enabled
    ++ (
      with all;
      [
        bcmath
        fileinfo
        gd
        mbstring
        pdo
        pdo_sqlite
      ]
      ++ lib.optionals (cfg.settings.DB_CONNECTION or "sqlite" == "mysql") [ pdo_mysql ]
      ++ lib.optionals (cfg.settings.DB_CONNECTION or "sqlite" == "pgsql") [ pdo_pgsql ]
    )
  );

  isSecret = v: lib.isAttrs v && v ? _secret && lib.isString v._secret;

  settingsEnv = lib.generators.toKeyValue {
    mkKeyValue = lib.flip lib.generators.mkKeyValueDefault "=" {
      mkValueString =
        v:
        if lib.isInt v then
          toString v
        else if lib.isString v then
          v
        else if v == true then
          "true"
        else if v == false then
          "false"
        else if isSecret v then
          builtins.hashString "sha256" v._secret
        else
          throw "unsupported type: ${builtins.typeOf v}";
  };
  };

  filteredSettings = lib.converge (lib.filterAttrsRecursive (
    _: v:
    !builtins.elem v [
      { }
      null
    ]
  )) cfg.settings;

  envFile = pkgs.writeText "2fauth.env" (settingsEnv filteredSettings);

  secretPaths = lib.mapAttrsToList (_: v: v._secret) (lib.filterAttrs (_: isSecret) cfg.settings);

  mkSecretReplacement = file: ''
    replace-secret ${
      lib.escapeShellArgs [
        (builtins.hashString "sha256" file)
        file
        "${cfg.stateDir}/.env"
      ]
    }
  '';

  artisan = "${phpPackage}/bin/php ${appDir}/artisan";

  setupScript = pkgs.writeShellScript "2fauth-setup" ''
    set -euo pipefail

    # Clear any stale bootstrap caches so config:cache picks up the new .env.
    rm -f "${cfg.stateDir}"/bootstrap/cache/*.php

    # Write .env with placeholders then substitute secrets in-place.
    install -T -m 0600 ${envFile} "${cfg.stateDir}/.env"
    ${lib.concatMapStrings mkSecretReplacement secretPaths}

    echo "Ensuring writable state directories exist..."
    for d in \
        storage/app/public \
        storage/app/public/icons \
        storage/app/logos \
        storage/app/imagesLink \
        storage/app/qrcodes \
        storage/framework/cache/data \
        storage/framework/sessions \
        storage/framework/views \
        storage/logs \
        bootstrap/cache \
        database; do
      mkdir -p "${cfg.stateDir}/$d"
    done

    echo "Seeding storage skeleton on first run..."
    SEED_FLAG="${cfg.stateDir}/.seeded"
    if [ ! -f "$SEED_FLAG" ]; then
      cp -rn "${appDir}/storage/." "${cfg.stateDir}/storage/" 2>/dev/null || true
      touch "$SEED_FLAG"
    fi
    # The store is read-only so cp preserves those permissions.
    # Forcibly make everything under storage writable by the service user.
    chmod -R u+rwX "${cfg.stateDir}/storage/"
    # public/ subtree needs group-read so nginx can serve icon files.
    chmod -R g+rX "${cfg.stateDir}/storage/app/public/"

    echo "Running artisan migrate..."
    ${artisan} migrate --force --no-interaction

    echo "Running artisan passport:install..."
    if [ ! -f "${cfg.stateDir}/storage/oauth-private.key" ]; then
      ${artisan} passport:install --force --no-interaction
    fi

    echo "Caching config, routes and views..."
    ${artisan} config:cache
    ${artisan} route:cache
    ${artisan} view:cache

    echo "Setup complete."
  '';

in
{
  options.services.twofauth = {
    enable = mkEnableOption "2FAuth: self-hosted TOTP/HOTP 2FA manager";

    package = mkPackageOption pkgs "twofauth" { };

    phpPackage = mkOption {
      type = types.package;
      default = pkgs.php84;
      defaultText = literalExpression "pkgs.php84";
      description = "PHP package (>= 8.4).";
    };

    user = mkOption {
      type = types.str;
      default = "twofauth";
      description = "System user to run 2FAuth as.";
    };

    group = mkOption {
      type = types.str;
      default = "twofauth";
      description = "System group to run 2FAuth as.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/2fauth";
      description = "Directory for persistent 2FAuth state (database, storage, .env).";
    };

    settings = mkOption {
      type = types.submodule {
        freeformType =
          with types;
          attrsOf (
            nullOr (oneOf [
              bool
              int
              str
              (submodule {
                options._secret = mkOption {
                  type = types.str;
                  description = "Path to a file containing the secret value.";
                };
              })
            ])
          );

        options = {
          APP_URL = mkOption {
            type = types.str;
            example = "https://2fa.example.com";
            description = "Public URL of the 2FAuth instance.";
          };

          APP_ENV = mkOption {
            type = types.enum [
              "local"
              "production"
              "testing"
            ];
            default = "production";
            description = "Laravel environment.";
          };

          DB_CONNECTION = mkOption {
            type = types.enum [
              "sqlite"
              "mysql"
              "pgsql"
              "sqlsrv"
            ];
            default = "sqlite";
            description = "Database driver.";
          };

          DB_DATABASE = mkOption {
            type = types.str;
            default = "/var/lib/2fauth/database/database.sqlite";
            description = "DB name, or absolute path for SQLite.";
          };

          LOG_CHANNEL = mkOption {
            type = types.enum [
              "errorlog"
              "daily"
              "single"
              "syslog"
              "stack"
            ];
            default = "errorlog";
            description = "Log channel. Use errorlog to send to journald.";
          };
        };
      };

      default = { };

      description = ''
        2FAuth environment variables written to `.env`.

        Plain values go here. For secrets (APP_KEY, passwords) use the
        `{ _secret = "/path/to/file"; }` form so they never enter the
        Nix store.

        See <https://docs.2fauth.app/getting-started/config/env-vars/>.
      '';
      example = literalExpression ''
        {
          APP_URL  = "https://2fa.example.com";
          APP_KEY  = { _secret = "/run/secrets/2fauth-app-key"; };
          APP_ENV  = "production";
          LOG_CHANNEL = "errorlog";
          MAIL_MAILER = "smtp";
          MAIL_HOST   = "mail.example.com";
          MAIL_PORT   = "587";
          MAIL_FROM_ADDRESS = "2fa@example.com";
        }
      '';
    };

    database = {
      createLocally = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Create a local PostgreSQL database and role.
          Sets DB_* in settings automatically via peer auth (no password needed).
        '';
      };

      name = mkOption {
        type = types.str;
        default = "twofauth";
        description = "PostgreSQL database name.";
      };

      user = mkOption {
        type = types.str;
        default = "twofauth";
        description = ''
          PostgreSQL role name. Must match the OS user that php-fpm and the
          setup service run as so that peer authentication works.
          Defaults to `twofauth`, matching the static system user this module
          creates.
        '';
      };
    };

    nginx = {
      enable = mkEnableOption "an nginx virtual host for 2FAuth";

      hostName = mkOption {
        type = types.str;
        example = "2fa.example.com";
        description = "Virtual host name.";
      };

      useSSL = mkOption {
        type = types.bool;
        default = true;
        description = "Obtain a Let's Encrypt certificate.";
      };

      extraLocationsConfig = mkOption {
        type = types.lines;
        default = "";
        description = "Extra directives for the root location block.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [

    {
      assertions = [
        {
          assertion = cfg.settings ? APP_KEY;
          message = ''
            services.twofauth.settings.APP_KEY must be set.
            Use { _secret = "/path/to/keyfile"; } to avoid storing it in the Nix store.
            Generate with: php artisan key:generate --show
          '';
        }
        {
          assertion = cfg.nginx.enable -> cfg.nginx.hostName != "";
          message = "services.twofauth.nginx.hostName must be set when nginx is enabled.";
        }
        {
          assertion = cfg.database.createLocally -> (cfg.settings.DB_CONNECTION or "pgsql" == "pgsql");
          message = "services.twofauth.database.createLocally only supports PostgreSQL.";
        }
      ];

      users.users.${cfg.user} = {
        group = cfg.group;
        isSystemUser = true;
      };

      users.groups.${cfg.group} = { };

      users.users.${config.services.nginx.user}.extraGroups = [ cfg.group ];

      systemd.tmpfiles.rules = [
        "d ${cfg.stateDir}                              0700 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/storage                      0700 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/storage/app/public           0750 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/storage/app/public/icons     0750 ${cfg.user} ${cfg.group} - -"
        "Z ${cfg.stateDir}/storage/app/public           0750 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/storage/app/logos            0700 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/storage/app/imagesLink       0700 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/storage/app/qrcodes          0700 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/storage/framework/cache/data 0700 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/storage/framework/sessions   0700 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/storage/framework/views      0700 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/storage/logs                 0700 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/bootstrap/cache              0700 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/database                     0700 ${cfg.user} ${cfg.group} - -"
      ];

      # Redirect all Laravel cache files into stateDir so the store stays
      # read-only. These env vars are official Laravel extension points.
      services.twofauth.settings = {
        APP_SERVICES_CACHE = mkDefault "${cfg.stateDir}/bootstrap/cache/services.php";
        APP_PACKAGES_CACHE = mkDefault "${cfg.stateDir}/bootstrap/cache/packages.php";
        APP_CONFIG_CACHE = mkDefault "${cfg.stateDir}/bootstrap/cache/config.php";
        APP_ROUTES_CACHE = mkDefault "${cfg.stateDir}/bootstrap/cache/routes-v7.php";
        APP_EVENTS_CACHE = mkDefault "${cfg.stateDir}/bootstrap/cache/events.php";
        LARAVEL_STORAGE_PATH = mkDefault "${cfg.stateDir}/storage";
      };

      systemd.services.twofauth-setup = {
        description = "2FAuth: database migrations and .env setup";
        wantedBy = [ "multi-user.target" ];
        before = [ "phpfpm-twofauth.service" ];
        after = [
          "network.target"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [ "network.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = setupScript;
          User = cfg.user;
          Group = cfg.group;
          StateDirectory = lib.removePrefix "/var/lib/" cfg.stateDir;
          StateDirectoryMode = "0700";

          ProtectHome = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          ProtectHostname = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          RestrictSUIDSGID = true;
          RemoveIPC = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
          NoNewPrivileges = true;
          CapabilityBoundingSet = "";
          AmbientCapabilities = "";
          SystemCallFilter = [
            "@system-service"
            "@chown"
            "~@resources"
          ];
          SystemCallArchitectures = "native";
          LockPersonality = true;
          MemoryDenyWriteExecute = false;
          RestrictRealtime = true;
          UMask = "0077";
        };

        path = [ pkgs.replace-secret ];

        environment = {
          # PHP tools (psysh/tinker) need a writable HOME.
          HOME = cfg.stateDir;
        };
      };

      services.phpfpm.pools.twofauth = {
        user = cfg.user;
        group = cfg.group;
        phpPackage = phpPackage;

        settings = {
          "listen.owner" = mkDefault config.services.nginx.user;
          "listen.group" = mkDefault config.services.nginx.group;
          "pm" = "dynamic";
          "pm.max_children" = 8;
          "pm.start_servers" = 2;
          "pm.min_spare_servers" = 1;
          "pm.max_spare_servers" = 4;
          "pm.max_requests" = 500;
        };

        phpEnv = { };
      };

      systemd.services.phpfpm-twofauth = {
        after = [ "twofauth-setup.service" ];
        requires = [ "twofauth-setup.service" ];
      };

      services.nginx = mkIf cfg.nginx.enable {
        enable = true;

        virtualHosts.${cfg.nginx.hostName} = {
          forceSSL = cfg.nginx.useSSL;
          enableACME = cfg.nginx.useSSL;

          root = "${appDir}/public";

          locations."/" = {
            index = "index.php";
            tryFiles = "$uri $uri/ /index.php?$query_string";
            extraConfig = cfg.nginx.extraLocationsConfig;
          };

          locations."= /favicon.ico".extraConfig = "access_log off; log_not_found off;";
          locations."= /robots.txt".extraConfig = "access_log off; log_not_found off;";

          locations."~ \\.php$".extraConfig = ''
            fastcgi_pass  unix:${config.services.phpfpm.pools.twofauth.socket};
            fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
            fastcgi_param DOCUMENT_ROOT   $realpath_root;
            include       ${config.services.nginx.package}/conf/fastcgi_params;
            fastcgi_hide_header X-Powered-By;
          '';

          locations."~ /\\.(?!well-known).*".extraConfig = "deny all;";

          extraConfig = ''
            charset utf-8;
            error_page 404 /index.php;
            add_header X-Frame-Options        "SAMEORIGIN"  always;
            add_header X-Content-Type-Options "nosniff"     always;
            add_header Referrer-Policy        "strict-origin-when-cross-origin" always;
          '';
        };
      };
    }

    (mkIf cfg.database.createLocally {
      services.twofauth.settings = {
        DB_CONNECTION = mkDefault "pgsql";
        DB_HOST = mkDefault "/run/postgresql";
        DB_PORT = mkDefault "5432";
        DB_DATABASE = mkDefault cfg.database.name;
        DB_USERNAME = mkDefault cfg.database.user;
      };

      services.postgresql = {
        enable = true;
        ensureDatabases = [ cfg.database.name ];
        ensureUsers = [
          {
            name = cfg.database.user;
            ensureDBOwnership = true;
          }
        ];

        authentication = mkAfter ''
          local ${cfg.database.name} ${cfg.database.user} peer map=twofauth
        '';
        identMap = "twofauth ${cfg.user} ${cfg.database.user}";
      };

      systemd.services.twofauth-setup = {
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
      };

      systemd.services.phpfpm-twofauth = {
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
      };
    })

    {
      meta.maintainers = with lib.maintainers; [ gaelj ];
    }
  ]);
}
