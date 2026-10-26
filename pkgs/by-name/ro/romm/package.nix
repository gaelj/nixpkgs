{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  buildNpmPackage,
  makeWrapper,
  nix-update-script,
  nixosTests,
  p7zip,
  python3,
  runtimeShell,
}:

stdenvNoCC.mkDerivation (
  finalAttrs:
  let
    inherit (finalAttrs.passthru) frontend pythonEnv;
  in
  {
    pname = "romm";
    version = "5.4.1";

    src = fetchFromGitHub {
      owner = "rommapp";
      repo = "romm";
      tag = finalAttrs.version;
      hash = "sha256-9go8Y4rmcrM2wTx8JwiIiR+WKltl1IlaKIVnZ6zzbYM=";
    };

    __structuredAttrs = true;
    strictDeps = true;

    nativeBuildInputs = [ makeWrapper ];

    # Upstream stamps this placeholder during its container release build.
    postPatch = ''
      substituteInPlace backend/__version__.py \
        --replace-fail '<version>' '${finalAttrs.version}'
    '';

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/romm
      cp -r backend $out/share/romm/backend
      ln -s ${frontend} $out/share/romm/frontend
      # njs handler for the internal /decode endpoint of upstream's nginx setup
      cp docker/nginx/js/decode.js $out/share/romm/decode.js

      wrap() {
        makeWrapper "$1" "$out/bin/$2" \
          --chdir $out/share/romm/backend \
          --set PYTHONPATH $out/share/romm/backend \
          --prefix PATH : ${lib.makeBinPath [ p7zip ]} \
          "''${@:3}"
      }

      wrap ${pythonEnv}/bin/alembic romm-migrate --add-flags "upgrade head"

      wrap ${pythonEnv}/bin/python romm-startup --add-flags "startup.py"

      # forwarded-allow-ips is left to gunicorn's FORWARDED_ALLOW_IPS handling
      # (default 127.0.0.1) rather than upstream's container-only "*".
      wrap ${pythonEnv}/bin/gunicorn romm --add-flags "main:app" \
        --set-default ROMM_HOST 127.0.0.1 \
        --set-default ROMM_PORT 8080 \
        --run 'export GUNICORN_CMD_ARGS="--bind=''${ROMM_HOST}:''${ROMM_PORT} --worker-class uvicorn_worker.UvicornWorker --no-control-socket --workers ''${WEB_SERVER_CONCURRENCY:-''${WEB_CONCURRENCY:-4}} --timeout ''${WEB_SERVER_TIMEOUT:-300} --keep-alive ''${WEB_SERVER_KEEPALIVE:-65} --max-requests ''${WEB_SERVER_MAX_REQUESTS:-1000} --max-requests-jitter ''${WEB_SERVER_MAX_REQUESTS_JITTER:-100} --worker-connections ''${WEB_SERVER_WORKER_CONNECTIONS:-1000} ''${GUNICORN_CMD_ARGS:-}"'

      # Upstream runs three rq workers: the default queues, library scans
      # (a long scan must not block anything else), and streaming teardowns
      # (a wedged emulator session must not block scans).
      rq_worker() {
        local name="$1" worker_class="$2"
        shift 2
        # --connection-class disables the Redis maint_notifications probe,
        # which fails against Redis < 8.2; --with-scheduler releases the
        # delayed jobs through which the watcher queues its rescans.
        wrap ${pythonEnv}/bin/rq "$name" \
          --add-flags "worker --path $out/share/romm/backend --worker-class handler.rq_worker.$worker_class --connection-class handler.redis_handler.RomMRedis --results-ttl ''${TASK_RESULT_TTL:-86400} --logging_level ''${LOGLEVEL:-INFO} --with-scheduler $*"
      }

      rq_worker romm-worker RomMWorker high default low
      rq_worker romm-scan-worker RomMWorker scans
      rq_worker romm-streaming-worker PreloadingWorker streaming

      # rq 2.12 replaced the standalone `rqscheduler` with its own cron
      # scheduler, driven by the task registry in tasks.cron_config.
      wrap ${pythonEnv}/bin/rq romm-scheduler \
        --add-flags "cron --path $out/share/romm/backend --connection-class handler.redis_handler.RomMRedis --logging-level ''${LOGLEVEL:-INFO} tasks.cron_config"

      cat > $out/bin/romm-watcher <<EOF
      #!${runtimeShell}
      export PYTHONPATH="$out/share/romm/backend"
      export PATH="${lib.makeBinPath [ p7zip ]}:\$PATH"
      cd "$out/share/romm/backend"
      exec ${pythonEnv}/bin/watchfiles --target-type command \
        "${pythonEnv}/bin/python watcher.py" "\''${1:-\''${ROMM_BASE_PATH:-/var/lib/romm}/library}"
      EOF
      chmod +x $out/bin/romm-watcher

      runHook postInstall
    '';

    passthru = {
      # Upstream is a uv workspace application (`package = false`), so the
      # backend is not pip-installable; it runs from source with its
      # dependencies on PYTHONPATH.
      pythonEnv = python3.withPackages (
        ps: with ps; [
          aiohttp
          alembic
          anyio
          apprise
          asyncssh
          authlib
          bcrypt
          colorama
          croniter
          cryptography
          defusedxml
          email-validator
          fastapi
          gunicorn
          httpx2
          itsdangerous
          jinja2
          joserfc
          mariadb
          mutagen
          mysql-connector-python
          opentelemetry-distro
          opentelemetry-exporter-otlp
          opentelemetry-instrumentation-aiohttp-client
          opentelemetry-instrumentation-fastapi
          opentelemetry-instrumentation-httpx
          opentelemetry-instrumentation-redis
          opentelemetry-instrumentation-sqlalchemy
          pillow
          psycopg
          pydantic
          pydash
          python-dotenv
          python-magic
          python-multipart
          python-socketio
          pyyaml
          redis
          rq
          sentry-sdk
          sqlalchemy
          starlette
          streaming-form-data
          strsimpy
          ua-parser
          unidecode
          uvicorn
          uvicorn-worker
          watchfiles
          yarl
          zipfile-inflate64
        ]
      );

      frontend = buildNpmPackage {
        pname = "romm-frontend";
        inherit (finalAttrs) version;
        src = "${finalAttrs.src}/frontend";

        npmDepsHash = "sha256-VvFiIZZo2yeWkP3Sa9zvvaoikCnLb9iLti76JBXg9aU=";
        npmFlags = [ "--ignore-scripts" ];
        makeCacheWritable = true;

        installPhase = ''
          runHook preInstall
          cp -r dist $out
          # merge static assets into the web root, as upstream's image does
          chmod u+w $out/assets
          cp -r assets/. $out/assets/
          runHook postInstall
        '';
      };

      tests = {
        inherit (nixosTests) romm;
      };

      updateScript = nix-update-script {
        extraArgs = [
          "--subpackage"
          "frontend"
        ];
      };
    };

    meta = {
      description = "Self-hosted ROM manager and player";
      homepage = "https://romm.app/";
      changelog = "https://github.com/rommapp/romm/releases/tag/${finalAttrs.version}";
      license = lib.licenses.agpl3Only;
      maintainers = with lib.maintainers; [
        denzonl
        jk
      ];
      mainProgram = "romm";
      platforms = lib.platforms.linux;
    };
  }
)
