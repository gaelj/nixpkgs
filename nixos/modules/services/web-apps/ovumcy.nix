{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.ovumcy;

  # All non-secret, fully static environment variables.
  # These are safe to write to the Nix store.
  staticEnv = {
    TZ = cfg.timezone;
    DEFAULT_LANGUAGE = cfg.defaultLanguage;
    REGISTRATION_MODE = cfg.registrationMode;
    PORT = toString cfg.port;
    HOST_BIND_ADDRESS = cfg.bindAddress;
    COOKIE_SECURE = if cfg.cookieSecure then "true" else "false";
    TRUST_PROXY_ENABLED = if cfg.trustProxy then "true" else "false";
    PROXY_HEADER = cfg.proxyHeader;
    TRUSTED_PROXIES = lib.concatStringsSep "," cfg.trustedProxies;
    SECRET_KEY_FILE = cfg.secretKeyFile;
  }
  // lib.optionalAttrs (cfg.database.driver == "sqlite") {
    DB_DRIVER = "sqlite";
    DB_PATH = "${cfg.dataDir}/ovumcy.db";
  }
  // lib.optionalAttrs (cfg.database.driver == "postgres" && cfg.database.postgres.dsnFile == null) {
    # Peer / trust auth: the DSN has no password, so it is safe in the store.
    DB_DRIVER = "postgres";
    DATABASE_URL = "postgres://${cfg.database.postgres.user}@${cfg.database.postgres.host}/${cfg.database.postgres.name}?sslmode=disable";
  }
  // lib.optionalAttrs (cfg.database.driver == "postgres" && cfg.database.postgres.dsnFile != null) {
    # Password auth: only the driver is set here; DATABASE_URL comes from
    # the operator-managed dsnFile loaded via EnvironmentFile below.
    DB_DRIVER = "postgres";
  }
  // cfg.extraEnv;

  envFile = (pkgs.formats.keyValue { }).generate "ovumcy.env" staticEnv;
  recommendedProxySettings = false;
in
{
  # ---------------------------------------------------------------------------
  # Options
  # ---------------------------------------------------------------------------
  options.services.ovumcy = {

    enable = lib.mkEnableOption "Ovumcy self-hosted cycle tracker";

    package = lib.mkPackageOption pkgs "ovumcy" { };

    # --- Runtime -----------------------------------------------------------

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "TCP port the Ovumcy server listens on.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address the server binds to.  Defaults to loopback; change only for an
        intentional private-network bind (not for direct public exposure).
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/ovumcy";
      description = "Directory that holds persistent data (SQLite file, etc.).";
    };

    secretKeyFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a file containing the SECRET_KEY value (32+ random bytes, hex).
        The path is passed to the application as SECRET_KEY_FILE; the key is
        read by the process at runtime and never stored in the Nix store.

        Generate a key:
          openssl rand -hex 32 > /path/to/secret-key
          chmod 400 /path/to/secret-key
          chown ovumcy /path/to/secret-key
      '';
    };

    # --- Localisation -------------------------------------------------------

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
      example = "Europe/Paris";
      description = "TZ value passed to the process.";
    };

    defaultLanguage = lib.mkOption {
      type = lib.types.enum [
        "en"
        "fr"
        "ru"
        "es"
      ];
      default = "en";
      description = "Default UI language (users can override from the UI).";
    };

    registrationMode = lib.mkOption {
      type = lib.types.enum [
        "open"
        "closed"
      ];
      default = "open";
      description = ''
        "open" - anyone can register.
        "closed" - self-service sign-up is disabled; use the CLI to provision accounts.
      '';
    };

    # --- TLS / proxy --------------------------------------------------------

    cookieSecure = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set COOKIE_SECURE=true when serving over HTTPS.";
    };

    trustProxy = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable TRUST_PROXY_ENABLED (only when behind a trusted reverse proxy).";
    };

    proxyHeader = lib.mkOption {
      type = lib.types.str;
      default = "X-Forwarded-For";
      description = "Header used to read the client IP when trust-proxy is enabled.";
    };

    trustedProxies = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "127.0.0.1"
        "::1"
      ];
      description = "List of trusted proxy addresses.";
    };

    # --- Database -----------------------------------------------------------

    database = {
      driver = lib.mkOption {
        type = lib.types.enum [
          "sqlite"
          "postgres"
        ];
        default = "sqlite";
        description = ''
          Storage backend.  "sqlite" is the simple baseline;
          "postgres" enables the advanced self-hosted path.
        '';
      };

      # Postgres-specific sub-options (ignored when driver = "sqlite").
      postgres = {
        host = lib.mkOption {
          type = lib.types.str;
          default = "/run/postgresql";
          description = "PostgreSQL host (or Unix socket directory for peer auth).";
        };

        name = lib.mkOption {
          type = lib.types.str;
          default = "ovumcy";
          description = "Database name.";
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "ovumcy";
          description = "PostgreSQL role used by the application.";
        };

        dsnFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Path to a file containing a single line of the form:

              DATABASE_URL=postgres://user:password@host:5432/dbname?sslmode=disable

            The file is loaded as a systemd EnvironmentFile so the password
            never enters the Nix store.  Leave null to use peer / trust
            authentication (recommended when postgres.enable = true and both
            services run on the same machine - no password needed).
          '';
        };
      };
    };

    # --- Extra environment --------------------------------------------------

    extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = lib.literalExpression ''{ LOG_LEVEL = "debug"; }'';
      description = ''
        Additional non-secret environment variables passed verbatim to the
        service.  Do not put secrets here; they would end up in the Nix store.
      '';
    };

    # --- Managed PostgreSQL sub-option --------------------------------------

    postgres = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          When true, NixOS creates the PostgreSQL database and role
          automatically.  Implies services.postgresql.enable = true.
          Use peer auth (leave database.postgres.dsnFile = null) when
          both services run on the same machine.
        '';
      };
    };

    # --- Nginx sub-option ---------------------------------------------------

    nginx = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          When true, NixOS creates an nginx virtual host that reverse-proxies
          to the Ovumcy backend and sets cookieSecure / trustProxy
          automatically when forceSSL = true.
        '';
      };

      hostname = lib.mkOption {
        type = lib.types.str;
        example = "ovumcy.example.com";
        description = "Public hostname for the nginx virtual host.";
      };

      enableACME = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use ACME / Let's Encrypt to obtain a TLS certificate.";
      };

      forceSSL = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Redirect HTTP → HTTPS.  Requires enableACME or a manual cert.";
      };

      extraConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Extra nginx location / server directives appended verbatim.";
      };
    };

  };

  # ---------------------------------------------------------------------------
  # Implementation
  # ---------------------------------------------------------------------------
  config = lib.mkIf cfg.enable {

    # --- System user & group ------------------------------------------------
    users.users.ovumcy = {
      isSystemUser = true;
      group = "ovumcy";
      home = cfg.dataDir;
      description = "Ovumcy service user";
    };
    users.groups.ovumcy = { };

    # --- Managed PostgreSQL -------------------------------------------------
    services.postgresql = lib.mkIf cfg.postgres.enable {
      enable = true;
      ensureDatabases = [ cfg.database.postgres.name ];
      ensureUsers = [
        {
          name = cfg.database.postgres.user;
          ensureDBOwnership = true;
        }
      ];
    };

    # --- systemd service ----------------------------------------------------
    systemd.services.ovumcy = {
      description = "Ovumcy cycle tracker";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ] ++ lib.optionals cfg.postgres.enable [ "postgresql.service" ];
      requires = lib.optionals cfg.postgres.enable [ "postgresql.service" ];

      serviceConfig = {
        User = "ovumcy";
        Group = "ovumcy";
        WorkingDirectory = "${cfg.package}/share/ovumcy";
        StateDirectory = baseNameOf cfg.dataDir;
        StateDirectoryMode = "0750";

        EnvironmentFile = [
          envFile
        ]
        ++ lib.optional (
          cfg.database.driver == "postgres" && cfg.database.postgres.dsnFile != null
        ) cfg.database.postgres.dsnFile;

        ExecStart = lib.escapeShellArgs [ "${cfg.package}/bin/ovumcy" ];

        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
        CapabilityBoundingSet = "";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        SystemCallFilter = "@system-service";
        SystemCallErrorNumber = "EPERM";

        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    services.nginx = lib.mkIf cfg.nginx.enable {
      enable = true;

      virtualHosts.${cfg.nginx.hostname} = {
        inherit (cfg.nginx) enableACME forceSSL;

        locations."/" = {
          recommendedProxySettings = false;
          proxyPass = "http://${cfg.bindAddress}:${toString cfg.port}";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host              $host;
            proxy_set_header X-Real-IP         $remote_addr;
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_buffering    off;
            proxy_read_timeout 300s;
          '';
        };

        extraConfig = cfg.nginx.extraConfig;
      };
    };

    # When nginx is enabled, flip the proxy-trust knobs automatically.
    services.ovumcy = lib.mkIf cfg.nginx.enable {
      cookieSecure = lib.mkDefault cfg.nginx.forceSSL;
      trustProxy = lib.mkDefault true;
    };

  };

  meta.maintainers = with lib.maintainers; [ gaelj ];
}
