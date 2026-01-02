# Koel NixOS Module

NixOS module for [Koel](https://koel.dev/) - a simple web-based personal audio streaming service.

## Features

- 🎵 Declarative Koel configuration
- 🗄️ SQLite database (zero configuration)
- 🔍 TNTSearch engine (no additional services needed)
- 🚀 Automatic PHP-FPM setup
- 🌐 Works with Caddy reverse proxy (automatic HTTPS)
- 📦 Fully declarative, NixOS-native
- ⚡ Perfect for homelab environments

## Quick Start

Add to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    koel-nix.url = "github:DzmingLi/koel-nix";
  };

  outputs = { self, nixpkgs, koel-nix }: {
    nixosConfigurations.yourhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        koel-nix.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

## Configuration

### Minimal Configuration (Homelab)

```nix
{ config, pkgs, ... }:

{
  services.koel = {
    enable = true;

    # Use agenix to manage the app key
    appKey = "/run/agenix/koel-app-key";

    listen = "/run/phpfpm/koel.sock";
    database.type = "sqlite-persistent";

    storage = {
      driver = "local";
      mediaPath = "/srv/music";
    };

    search.driver = "tntsearch";
    streaming.method = "php";
  };

  # Caddy reverse proxy with automatic HTTPS
  services.caddy = {
    enable = true;
    # email = "your-email@example.com";  # Optional: for Let's Encrypt notifications

    virtualHosts."music.example.com".extraConfig = ''
      root * /var/lib/koel/public
      php_fastcgi unix//run/phpfpm/koel.sock
      file_server
      encode gzip
    '';
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
```

## Setup Steps

### 1. Setup Application Key with agenix

First, add agenix to your flake inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    koel-nix.url = "github:DzmingLi/koel-nix";
    agenix.url = "github:ryantm/agenix";
  };

  outputs = { self, nixpkgs, koel-nix, agenix }: {
    nixosConfigurations.yourhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        koel-nix.nixosModules.default
        agenix.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

Generate and encrypt the app key:

```bash
# Generate a random key
head -c 32 /dev/urandom | base64 > koel-app-key.tmp

# Add "base64:" prefix
echo "base64:$(cat koel-app-key.tmp)" > koel-app-key.txt

# Encrypt with agenix
agenix -e koel-app-key.age

# Clean up
rm koel-app-key.tmp koel-app-key.txt
```

Then add to your configuration:

```nix
age.secrets.koel-app-key = {
  file = ./koel-app-key.age;
  mode = "0400";
  owner = "koel";
};
```

### 2. Prepare Music Directory

```bash
sudo mkdir -p /srv/music
# Copy your music files here
```

### 3. Apply Configuration

```bash
sudo nixos-rebuild switch
```

### 4. Access Koel

Open your browser and navigate to the configured URL (e.g., `http://music.local`). On first access, you'll be prompted to create an admin account.

## Configuration Options

### Basic Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services.koel.enable` | bool | false | Enable Koel service |
| `services.koel.appName` | string | "Koel" | Application name |
| `services.koel.url` | string | "http://localhost" | Koel access URL |
| `services.koel.appKey` | string | - | Application encryption key (required). Use agenix path `/run/agenix/koel-app-key` or plaintext `base64:YOUR_KEY` |
| `services.koel.listen` | string | "127.0.0.1:9000" | PHP-FPM listen address |
| `services.koel.version` | string | "v8.2.0" | Koel version to install |

### Database

For homelab, SQLite is recommended (no extra services):

```nix
services.koel.database.type = "sqlite-persistent";
```

Supported types: `sqlite-persistent`, `mysql`, `mariadb`, `pgsql`

### Storage

```nix
services.koel.storage = {
  driver = "local";           # local, sftp, s3, dropbox
  mediaPath = "/srv/music";   # Music files path (required for local)
  artifactsPath = null;       # Optional: cache/transcoded files path
};
```

### Search

TNTSearch is recommended for homelab (no extra services):

```nix
services.koel.search.driver = "tntsearch";
```

Supported drivers: `tntsearch`, `database`, `algolia`, `meilisearch`

### Streaming

Default is `php` for simpler setup. Use `x-accel-redirect` with nginx for better performance.

```nix
services.koel.streaming = {
  method = "php";             # php, x-sendfile, x-accel-redirect
  transcodeFlac = true;       # Enable FLAC to MP3 transcoding
  transcodeBitRate = 128;     # Transcoding bitrate (kbps)
};
```

### Performance

```nix
services.koel.performance = {
  maxScanTime = 600;          # Max scan time (seconds)
  memoryLimit = null;         # Memory limit (MB), null = unlimited
};

services.koel.poolConfig = {
  "pm" = "dynamic";
  "pm.max_children" = 32;
  "pm.start_servers" = 2;
  "pm.min_spare_servers" = 2;
  "pm.max_spare_servers" = 4;
};
```


## System Services

The module automatically creates these systemd services:

- `koel-setup.service` - Initialize and update Koel
- `koel-scan.service` - Media library scanning
- `koel-scan.timer` - Automatic daily scanning

### Common Commands

```bash
# Manual media library scan
sudo systemctl start koel-scan.service

# View Koel logs
sudo journalctl -u koel-setup.service

# View PHP-FPM logs
sudo journalctl -u phpfpm-koel.service

# View Caddy logs
sudo journalctl -u caddy.service

# Restart PHP-FPM
sudo systemctl restart phpfpm-koel.service
```

## Migration & Backup

### Backup

Backup these locations:

```bash
# SQLite database
/var/lib/koel/database/database.sqlite

# Music files
/srv/music  # or your configured mediaPath

# Quick backup script
sudo cp /var/lib/koel/database/database.sqlite \
  ~/koel-backup-$(date +%Y%m%d).sqlite
```

### Migration

Moving to a new server is simple:

```bash
# On old server
sudo systemctl stop phpfpm-koel.service
sudo tar czf koel-backup.tar.gz /var/lib/koel /srv/music

# Transfer to new server
scp koel-backup.tar.gz newserver:~

# On new server
sudo tar xzf koel-backup.tar.gz -C /
sudo nixos-rebuild switch
```

## FAQ

### How do I log in for the first time?

On first access, Koel will prompt you to create an admin account. Fill in your email and password.

### How long does media scanning take?

Depends on library size. Automatic scanning runs daily, or trigger manually:
```bash
sudo systemctl start koel-scan.service
```

### FLAC files won't play?

Enable transcoding:
```nix
services.koel.streaming.transcodeFlac = true;
```


### How do I update Koel?

Change the version and rebuild:
```nix
services.koel.version = "v8.3.0";  # New version
```
```bash
sudo nixos-rebuild switch
```

### Caddy isn't getting SSL certificates?

Check:
1. Domain DNS points to your server
2. Ports 80 and 443 are open
3. View logs: `journalctl -u caddy.service`



## Directory Structure

```
/var/lib/koel/              # Koel application directory
├── public/                 # Web root
├── storage/                # Storage directory
│   ├── framework/          # Laravel framework files
│   ├── logs/               # Application logs
│   └── database/           # SQLite database
│       └── database.sqlite # Database file
└── .env                    # Environment config (auto-generated)

/srv/music/                 # Music files (configurable)
/run/phpfpm/koel.sock       # PHP-FPM socket
```


## License

MIT License. See [LICENSE](LICENSE) file for details.

Koel itself is also MIT licensed.

## Links

- [Koel Official Site](https://koel.dev/)
- [Koel Documentation](https://docs.koel.dev/)
- [Koel GitHub](https://github.com/koel/koel)
- [NixOS](https://nixos.org/)
- [Caddy](https://caddyserver.com/)
