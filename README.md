A fork of the linuxserver.io [smokeping container](https://github.com/linuxserver/docker-smokeping)
with speedtest probes for monitoring internet connection performance.

## Speedtest Support

This container includes **two speedtest implementations**:

1. **Ookla Speedtest CLI** (Official) - `/usr/bin/speedtest`
   - Probe module: `speedtest.pm`
   - Recommended for most users
   - Supports ping, download, and upload measurements
   - Uses result caching to minimize API calls

2. **speedtest-cli** (Python implementation) - `/usr/bin/speedtest-cli`
   - Probe module: `speedtestcli.pm`
   - Alternative implementation
   - Supports download and upload measurements

## Quick Start

Run the container with:
```bash
docker run -p 8080:80 --rm ghcr.io/alekc/docker-smokeping-speedtest:latest
```

Access the web interface at `http://localhost:8080`

## Configuration

### Finding Nearest Servers

**For Ookla speedtest:**
```bash
docker exec <container> speedtest -L
```

**For speedtest-cli:**
```bash
docker exec <container> speedtest-cli --list | head
```

### Presentation

Make sure that the Presentation file contains the adjusted maximum value,
otherwise the overview charts will not show speedtest results.
The container already contains adjusted defaults.

```ini
+ overview

width = 600
height = 50
range = 10h
max_rtt = 1000000000
```

### Probes Configuration

#### Option 1: Ookla Speedtest (Recommended)

The Ookla implementation uses intelligent caching - when measuring ping, download, and upload for the same server,
only one speedtest execution occurs within 60 seconds, with results cached and reused.

```ini
# Ookla speedtest probes
+ speedtest
binary = /usr/bin/speedtest
timeout = 300
forks = 1
step = 3600
offset = random
pings = 3

++ speedtest-download
measurement = download

++ speedtest-upload
measurement = upload

++ speedtest-ping
measurement = ping
```

#### Option 2: Python speedtest-cli

```ini
# Python speedtest-cli probes
+ speedtestcli
binary = /usr/bin/speedtest-cli
timeout = 300
forks = 1
step = 3600
offset = random
pings = 3

++ speedtestcli-download
measurement = download

++ speedtestcli-upload
measurement = upload
```

### Targets Configuration

#### Using Ookla Speedtest

```ini
++++ ookla_download_from_server
menu = Download from Server
title = Server Name (download)
probe = speedtest-download
server = 12345
measurement = download
host = dummy.com

++++ ookla_upload_to_server
menu = Upload to Server
title = Server Name (upload)
probe = speedtest-upload
server = 12345
measurement = upload
host = dummy.com

++++ ookla_ping_to_server
menu = Ping to Server
title = Server Name (ping)
probe = speedtest-ping
server = 12345
measurement = ping
host = dummy.com
```

**Note:** Replace `12345` with your server ID from `speedtest -L`

#### Using speedtest-cli

```ini
++++ cli_download_from_server
menu = Download from Server
title = Server Name (download)
probe = speedtestcli-download
server = 12345
measurement = download
host = dummy.com

++++ cli_upload_to_server
menu = Upload to Server
title = Server Name (upload)
probe = speedtestcli-upload
server = 12345
measurement = upload
host = dummy.com
```

**Note:** Replace `12345` with your server ID from `speedtest-cli --list`

## Features

### Intelligent Caching (Ookla only)
- Results are cached for 60 seconds per server
- Ping, download, and upload measurements share the same test result
- Reduces API calls from 3 to 1 per measurement cycle
- Thread-safe with atomic file locks to prevent race conditions

### Environment Variables

- `SMOKEPING_SPEEDTEST_CACHE` - Cache directory path (default: `/tmp/smokeping-speedtest-cache`)

## Credits

Based on:
- [linuxserver/docker-smokeping](https://github.com/linuxserver/docker-smokeping)
- [mad-ady/smokeping-speedtest](https://github.com/mad-ady/smokeping-speedtest)
