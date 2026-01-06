{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.koel;

  user = "koel";
  group = "koel";
  stateDir = "/var/lib/koel";

  koelEnvTemplate = pkgs.writeText "koel.env.template" ''
    APP_NAME=${cfg.appName}
    APP_ENV=${cfg.environment}
    APP_DEBUG=${boolToString cfg.debug}
    APP_URL=${cfg.url}
    ${if cfg.appKeyFile == null then ''
    APP_KEY=${cfg.appKey}
    '' else ''
    # APP_KEY will be set at runtime from ${cfg.appKeyFile}
    ''}

    ${optionalString (cfg.trustedHosts != []) ''
    TRUSTED_HOSTS=${concatStringsSep "," cfg.trustedHosts}
    ''}

    # Database
    DB_CONNECTION=${cfg.database.type}
    ${optionalString (cfg.database.type != "sqlite-persistent") ''
    DB_HOST=${cfg.database.host}
    DB_PORT=${toString cfg.database.port}
    DB_DATABASE=${cfg.database.name}
    DB_USERNAME=${cfg.database.user}
    ${if cfg.database.passwordFile == null then ''
    DB_PASSWORD=
    '' else ''
    # DB_PASSWORD will be set at runtime from ${cfg.database.passwordFile}
    ''}
    ''}

    # Storage
    STORAGE_DRIVER=${cfg.storage.driver}
    ${optionalString (cfg.storage.driver == "local" && cfg.storage.mediaPath != null) ''
    MEDIA_PATH=${cfg.storage.mediaPath}
    ''}
    ${optionalString (cfg.storage.artifactsPath != null) ''
    ARTIFACTS_PATH=${cfg.storage.artifactsPath}
    ''}

    # Search
    SCOUT_DRIVER=${cfg.search.driver}
    ${optionalString (cfg.search.driver == "meilisearch") ''
    MEILISEARCH_HOST=${cfg.search.meilisearch.host}
    ${if cfg.search.meilisearch.keyFile == null then ''
    MEILISEARCH_KEY=
    '' else ''
    # MEILISEARCH_KEY will be set at runtime from ${cfg.search.meilisearch.keyFile}
    ''}
    ''}

    # Streaming
    STREAMING_METHOD=${cfg.streaming.method}
    ${optionalString cfg.streaming.transcodeFlac ''
    TRANSCODE_FLAC=true
    ${optionalString (cfg.streaming.ffmpegPath != null) ''
    FFMPEG_PATH=${cfg.streaming.ffmpegPath}
    ''}
    TRANSCODE_BIT_RATE=${toString cfg.streaming.transcodeBitRate}
    ''}

    # Features
    ALLOW_DOWNLOAD=${boolToString cfg.features.allowDownload}
    BACKUP_ON_DELETE=${boolToString cfg.features.backupOnDelete}
    IGNORE_DOT_FILES=${boolToString cfg.features.ignoreDotFiles}

    # Performance
    APP_MAX_SCAN_TIME=${toString cfg.performance.maxScanTime}
    ${optionalString (cfg.performance.memoryLimit != null) ''
    MEMORY_LIMIT=${toString cfg.performance.memoryLimit}
    ''}

    # Laravel
    BROADCAST_CONNECTION=log
    CACHE_DRIVER=${cfg.cache.driver}
    FILESYSTEM_DISK=local
    QUEUE_CONNECTION=${cfg.queue.connection}
    SESSION_DRIVER=${cfg.session.driver}
    SESSION_LIFETIME=${toString cfg.session.lifetime}

    ${cfg.extraConfig}
  '';

  phpPackage = pkgs.php82.withExtensions ({ enabled, all }: with all; enabled ++ [
    exif
    gd
    fileinfo
    redis
    imagick
    xsl
  ]);

  composerEnv = import "${pkgs.path}/pkgs/build-support/php/composer/env.nix" {
    inherit phpPackage;
    inherit (pkgs) stdenv lib;
  };

in {
  options.services.koel = {
    enable = mkEnableOption "Koel music streaming server";

    dataDir = mkOption {
      type = types.path;
      default = stateDir;
      description = "Directory where Koel data and application files are stored.";
    };

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = ''
        Koel package to use. If null, the module will clone from Git and build automatically.
        You can also point this to a local directory with Koel source code.
      '';
    };

    version = mkOption {
      type = types.str;
      default = "v8.2.0";
      description = "Koel version/tag to use when cloning from Git. Only used if package is null.";
    };

    appName = mkOption {
      type = types.str;
      default = "Koel";
      description = "Application name.";
    };

    environment = mkOption {
      type = types.enum [ "local" "production" ];
      default = "production";
      description = "Application environment.";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Enable debug mode.";
    };

    url = mkOption {
      type = types.str;
      default = "http://localhost";
      example = "https://music.example.com";
      description = "The URL where Koel will be accessible.";
    };

    appKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Application key for encryption. Generate with:
        head -c 32 /dev/urandom | base64
        Either appKey or appKeyFile must be set.
      '';
    };

    appKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        File containing the application key for encryption.
        Either appKey or appKeyFile must be set.
      '';
    };

    trustedHosts = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "localhost" "192.168.0.1" "music.example.com" ];
      description = "List of trusted hostnames for accessing Koel.";
    };

    listen = mkOption {
      type = types.str;
      default = "127.0.0.1:9000";
      example = "/run/phpfpm/koel.sock";
      description = ''
        Where PHP-FPM should listen. Can be a TCP address (host:port) or a Unix socket path.
        Use Unix socket for better performance with reverse proxies on the same host.
      '';
    };

    database = {
      type = mkOption {
        type = types.enum [ "mysql" "mariadb" "pgsql" "sqlite-persistent" ];
        default = "sqlite-persistent";
        description = "Database type to use.";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Database host.";
      };

      port = mkOption {
        type = types.port;
        default = 3306;
        description = "Database port.";
      };

      name = mkOption {
        type = types.str;
        default = "koel";
        description = "Database name.";
      };

      user = mkOption {
        type = types.str;
        default = "koel";
        description = "Database user.";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing the database password.";
      };
    };

    storage = {
      driver = mkOption {
        type = types.enum [ "local" "sftp" "s3" "dropbox" ];
        default = "local";
        description = "Storage driver for media files.";
      };

      mediaPath = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/srv/music";
        description = "Absolute path to media files (required for local storage).";
      };

      artifactsPath = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to store artifacts like transcoded files.";
      };
    };

    search = {
      driver = mkOption {
        type = types.enum [ "tntsearch" "database" "algolia" "meilisearch" ];
        default = "tntsearch";
        description = "Full text search driver.";
      };

      meilisearch = {
        host = mkOption {
          type = types.str;
          default = "http://127.0.0.1:7700";
          description = "MeiliSearch host URL.";
        };

        keyFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "File containing MeiliSearch API key.";
        };
      };
    };

    streaming = {
      method = mkOption {
        type = types.enum [ "php" "x-sendfile" "x-accel-redirect" ];
        default = "php";
        description = "Streaming method. Use x-accel-redirect with nginx for better performance.";
      };

      transcodeFlac = mkOption {
        type = types.bool;
        default = true;
        description = "Enable FLAC to MP3 transcoding on the fly.";
      };

      ffmpegPath = mkOption {
        type = types.nullOr types.path;
        default = "${pkgs.ffmpeg}/bin/ffmpeg";
        description = "Path to ffmpeg binary for transcoding.";
      };

      transcodeBitRate = mkOption {
        type = types.int;
        default = 128;
        description = "Bit rate for transcoded audio in kbps.";
      };
    };

    features = {
      allowDownload = mkOption {
        type = types.bool;
        default = true;
        description = "Allow song downloads.";
      };

      backupOnDelete = mkOption {
        type = types.bool;
        default = false;
        description = "Create backup when deleting songs.";
      };

      ignoreDotFiles = mkOption {
        type = types.bool;
        default = true;
        description = "Ignore dot files and folders during media scan.";
      };
    };

    performance = {
      maxScanTime = mkOption {
        type = types.int;
        default = 600;
        description = "Maximum scan time in seconds.";
      };

      memoryLimit = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Memory limit in MB for scanning process.";
      };
    };

    cache = {
      driver = mkOption {
        type = types.enum [ "file" "redis" "memcached" ];
        default = "file";
        description = "Cache driver.";
      };
    };

    queue = {
      connection = mkOption {
        type = types.enum [ "sync" "database" "redis" ];
        default = "sync";
        description = "Queue connection driver.";
      };
    };

    session = {
      driver = mkOption {
        type = types.enum [ "file" "cookie" "database" "redis" ];
        default = "file";
        description = "Session driver.";
      };

      lifetime = mkOption {
        type = types.int;
        default = 120;
        description = "Session lifetime in minutes.";
      };
    };

    poolConfig = mkOption {
      type = with types; attrsOf (oneOf [ str int bool ]);
      default = {
        "pm" = "dynamic";
        "pm.max_children" = 32;
        "pm.start_servers" = 2;
        "pm.min_spare_servers" = 2;
        "pm.max_spare_servers" = 4;
        "pm.max_requests" = 500;
      };
      description = "Options for the Koel PHP pool.";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Extra configuration to append to .env file.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.caddy.serviceConfig.ReadWritePaths = mkIf (hasPrefix "/" cfg.listen) (mkAfter [
      (concatStringsSep "/" (init (splitString "/" cfg.listen)))
    ]);

    assertions = [
      {
        assertion = cfg.storage.driver == "local" -> cfg.storage.mediaPath != null;
        message = "services.koel.storage.mediaPath must be set when using local storage driver";
      }
      {
        assertion = (cfg.appKey != null) != (cfg.appKeyFile != null);
        message = "Either services.koel.appKey or services.koel.appKeyFile must be set (but not both)";
      }
    ];

    users.users.${user} = {
      isSystemUser = true;
      group = group;
      home = stateDir;
      createHome = true;
      homeMode = "0755";
    };

    users.groups.${group} = {};

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0755 ${user} ${group} -"
    ];

    services.phpfpm.pools.koel = {
      user = user;
      group = group;
      phpPackage = phpPackage;
      settings = {
        "listen" = cfg.listen;
        "listen.owner" = config.services.caddy.user;
        "listen.group" = config.services.caddy.group;
        "listen.mode" = "0660";
      } // cfg.poolConfig;
    };

    systemd.services.koel-setup = {
      description = "Koel setup service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ] ++ optional (cfg.database.type == "mysql" || cfg.database.type == "mariadb") "mysql.service"
                                     ++ optional (cfg.database.type == "pgsql") "postgresql.service";

      serviceConfig = {
        Type = "oneshot";
        User = user;
        Group = group;
        WorkingDirectory = stateDir;
        RemainAfterExit = true;
      };

      path = [ phpPackage pkgs.nodejs pkgs.nodejs.pkgs.npm pkgs.git pkgs.unzip pkgs.bash pkgs.coreutils ];

      script = let
        targetVersion = if cfg.package != null then "custom" else cfg.version;
      in ''
        # Check if we need to setup or update
        NEEDS_SETUP=false
        if [ ! -f "${stateDir}/.koel-version" ]; then
          NEEDS_SETUP=true
          echo "First time setup..."
        elif [ "$(cat ${stateDir}/.koel-version)" != "${targetVersion}" ]; then
          NEEDS_SETUP=true
          echo "Version changed, updating..."
        fi

        if [ "$NEEDS_SETUP" = true ]; then
          echo "Setting up Koel ${targetVersion}..."

          ${if cfg.package != null then ''
            # Use provided package
            echo "Using provided Koel package..."
            rm -rf ${stateDir}/*
            cp -r ${cfg.package}/* ${stateDir}/ || true
          '' else ''
            # Clone from Git if not exists or update
            if [ ! -d "${stateDir}/.git" ]; then
              echo "Cloning Koel from GitHub..."
              rm -rf ${stateDir}/*
              ${pkgs.git}/bin/git clone --depth 1 --branch ${cfg.version} \
                https://github.com/koel/koel.git ${stateDir}
            else
              echo "Updating existing Koel repository..."
              cd ${stateDir}
              ${pkgs.git}/bin/git fetch --depth 1 origin tag ${cfg.version}
              ${pkgs.git}/bin/git checkout ${cfg.version}
            fi
          ''}

          # Set up storage directories before composer install
          echo "Setting up storage directories..."
          mkdir -p ${stateDir}/storage/framework/{sessions,views,cache}
          mkdir -p ${stateDir}/storage/logs
          mkdir -p ${stateDir}/storage/app/public
          mkdir -p ${stateDir}/bootstrap/cache
          mkdir -p ${stateDir}/database

          # Create empty SQLite database file if using sqlite-persistent
          ${optionalString (cfg.database.type == "sqlite-persistent") ''
          if [ ! -f ${stateDir}/database/koel.sqlite ]; then
            echo "Creating SQLite database file..."
            touch ${stateDir}/database/koel.sqlite
            chmod 644 ${stateDir}/database/koel.sqlite
          fi
          ''}

          # Generate .env file before running composer
          echo "Generating environment configuration..."
          rm -f ${stateDir}/.env
          cp ${koelEnvTemplate} ${stateDir}/.env
          chmod 600 ${stateDir}/.env

          # Add secrets from files
          ${optionalString (cfg.appKeyFile != null) ''
          echo "APP_KEY=$(cat ${cfg.appKeyFile})" >> ${stateDir}/.env
          ''}
          ${optionalString (cfg.database.type != "sqlite-persistent" && cfg.database.passwordFile != null) ''
          echo "DB_PASSWORD=$(cat ${cfg.database.passwordFile})" >> ${stateDir}/.env
          ''}
          ${optionalString (cfg.search.driver == "meilisearch" && cfg.search.meilisearch.keyFile != null) ''
          echo "MEILISEARCH_KEY=$(cat ${cfg.search.meilisearch.keyFile})" >> ${stateDir}/.env
          ''}

          # Install PHP dependencies
          echo "Installing PHP dependencies with Composer..."
          cd ${stateDir}
          export COMPOSER_ALLOW_SUPERUSER=1
          ${phpPackage.packages.composer}/bin/composer install \
            --no-dev \
            --no-interaction \
            --no-progress \
            --optimize-autoloader

          # Install and build frontend assets
          echo "Installing Node.js dependencies..."
          export npm_config_script_shell=${pkgs.bash}/bin/bash
          ${pkgs.nodejs}/bin/npm install --no-audit --no-fund

          echo "Building frontend assets..."
          export npm_config_script_shell=${pkgs.bash}/bin/bash
          ${pkgs.nodejs}/bin/npm run build

          # Set permissions - allow web server to read files
          chmod 755 ${stateDir}
          chmod 755 ${stateDir}/public
          chmod -R 755 ${stateDir}/storage
          chmod -R 755 ${stateDir}/bootstrap/cache

          # Run database migrations
          echo "Running database migrations..."
          cd ${stateDir}
          ${phpPackage}/bin/php artisan migrate --force

          # Cache optimization
          echo "Optimizing Laravel caches..."
          ${phpPackage}/bin/php artisan config:cache
          ${phpPackage}/bin/php artisan route:cache
          ${phpPackage}/bin/php artisan view:cache

          # Create search index
          echo "Creating search index..."
          ${phpPackage}/bin/php artisan koel:search:import || true

          # Mark version
          echo "${targetVersion}" > ${stateDir}/.koel-version

          echo "Koel setup completed successfully!"
        else
          # Just update .env
          echo "Updating environment configuration..."
          rm -f ${stateDir}/.env
          cp ${koelEnvTemplate} ${stateDir}/.env
          chmod 600 ${stateDir}/.env

          # Add secrets from files
          ${optionalString (cfg.appKeyFile != null) ''
          echo "APP_KEY=$(cat ${cfg.appKeyFile})" >> ${stateDir}/.env
          ''}
          ${optionalString (cfg.database.type != "sqlite-persistent" && cfg.database.passwordFile != null) ''
          echo "DB_PASSWORD=$(cat ${cfg.database.passwordFile})" >> ${stateDir}/.env
          ''}
          ${optionalString (cfg.search.driver == "meilisearch" && cfg.search.meilisearch.keyFile != null) ''
          echo "MEILISEARCH_KEY=$(cat ${cfg.search.meilisearch.keyFile})" >> ${stateDir}/.env
          ''}

          # Ensure permissions are correct
          chmod 755 ${stateDir}
          chmod 755 ${stateDir}/public

          echo "Koel is up to date."
        fi
      '';
    };

    systemd.services.koel-queue = mkIf (cfg.queue.connection != "sync") {
      description = "Koel queue worker";
      wantedBy = [ "multi-user.target" ];
      after = [ "koel-setup.service" ];

      serviceConfig = {
        Type = "simple";
        User = user;
        Group = group;
        WorkingDirectory = stateDir;
        Restart = "always";
        RestartSec = 10;
      };

      path = [ phpPackage ];

      script = ''
        ${phpPackage}/bin/php artisan queue:work --tries=3 --timeout=90
      '';
    };

    systemd.timers.koel-scan = {
      description = "Koel media scan timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    systemd.services.koel-scan = {
      description = "Koel media scan service";
      after = [ "koel-setup.service" ];

      serviceConfig = {
        Type = "oneshot";
        User = user;
        Group = group;
        WorkingDirectory = stateDir;
      };

      path = [ phpPackage ];

      script = ''
        ${phpPackage}/bin/php artisan koel:sync
      '';
    };
  };
}
