# retroarch-zarf

A [Zarf](https://zarf.dev) package that bundles [LinuxServer RetroArch](https://github.com/linuxserver/docker-retroarch) for [UDS Core](https://docs.defenseunicorns.com/core/) and airgapped Kubernetes deployments.

**Repository:** https://github.com/MrJoeeS/retroarch_zarf

RetroArch is a frontend for emulators, game engines, and media players. The LinuxServer container exposes a full RetroArch desktop through a web browser over Selkies.

**URL after deploy on UDS:** `https://retroarch.<domain>` (e.g. `https://retroarch.uds.dev`)

**Image:** `lscr.io/linuxserver/retroarch:latest`

## What this repo provides

- **`zarf.yaml`** — Package definition with two components: UDS policy exemptions, then the Helm deployment
- **`chart/`** — Helm chart with Deployment, PVC, Service, and UDS `Package` CR for Istio ingress
- **`manifests/`** — UDS `Exemption` CR for Pepr policies required by the LinuxServer image
- **`values/upstream-values.yaml`** — Deploy-time Helm values wired to Zarf variables
- **`.github/workflows/release.yml`** — Builds `amd64` and `arm64` Zarf packages on every version tag

## Prerequisites

- A UDS Core cluster (or any Kubernetes cluster initialized with Zarf via `zarf init`)
- [Zarf CLI](https://docs.zarf.dev/getting-started/) v0.79.0 or newer
- [UDS CLI](https://docs.defenseunicorns.com/core/) for UDS deployments
- Sufficient cluster storage for a PersistentVolumeClaim (default 10Gi)

## Quick start (UDS)

```bash
make create
uds zarf package deploy zarf-package-retroarch-*.tar.zst --confirm
```

Verify the UDS Operator processed the package:

```bash
uds zarf tools kubectl get package -n retroarch
```

Then open `https://retroarch.uds.dev` in your browser.

Without UDS ingress (any Zarf cluster):

```bash
zarf connect retroarch
```

## Quick start (generic Kubernetes)

Download a release package from [GitHub Releases](https://github.com/MrJoeeS/retroarch_zarf/releases), then:

```bash
zarf package deploy zarf-package-retroarch-amd64-0.1.0.tar.zst --confirm
```

Pass configuration non-interactively:

```bash
zarf package deploy zarf-package-retroarch-amd64-0.1.0.tar.zst \
  --confirm \
  --set RETROARCH_CUSTOM_USER=admin \
  --set RETROARCH_PASSWORD='change-me'
```

## ROMs, cores, and screenshots

RetroArch settings, saves, and your game library all live on the cluster **PersistentVolumeClaim** mounted at `/config` inside the pod. ROMs are **not** bundled in the Zarf package — copy them in after deploy.

### Where files live in the container

| Path | Purpose |
|---|---|
| `/config/roms/` | Recommended location for ROM files (create subfolders per system) |
| `/config/.config/retroarch/cores/` | Emulator cores (`.so` files) |
| `/config/.config/retroarch/screenshots/` | In-game screenshots |
| `/config/.config/retroarch/saves/` | Save files |
| `/config/.config/retroarch/states/` | Save states |

Suggested layout under `/config/roms/`:

```text
/config/roms/
├── gba/    # .gba
├── gbc/    # .gbc
├── gb/     # .gb
├── snes/   # .sfc, .smc
└── ...
```

Sort by file extension so RetroArch picks the right core when you use **Load Content**.

### Copy ROMs from your machine

You need `kubectl` access to the cluster (or `uds zarf tools kubectl` on UDS). Replace the local path with your ROM folder.

**Linux / macOS / WSL (Windows):**

```bash
# Resolve the running pod
POD=$(kubectl get pod -n retroarch -l app.kubernetes.io/name=retroarch -o jsonpath='{.items[0].metadata.name}')

# Create ROM directories (once)
kubectl exec -n retroarch deploy/retroarch -- sh -c \
  'mkdir -p /config/roms/gba /config/roms/gbc /config/roms/gb && chown -R abc:abc /config/roms'

# Copy a single ROM
kubectl cp "/path/to/your/game.gba" "retroarch/${POD}:/config/roms/gba/game.gba"

# Copy an entire folder (run from WSL if ROMs are on a Windows drive)
ROM_SRC="/mnt/c/Users/you/OneDrive/Documents/roms/systems/gba"
for f in "$ROM_SRC"/*; do
  ext="${f##*.}"
  case "$ext" in
    gba) sub=gba ;; gbc) sub=gbc ;; gb) sub=gb ;; *) continue ;;
  esac
  kubectl cp "$f" "retroarch/${POD}:/config/roms/${sub}/$(basename "$f")"
done

# Fix ownership so RetroArch can read the files
kubectl exec -n retroarch deploy/retroarch -- chown -R abc:abc /config/roms
```

**UDS:** prefix commands with `uds zarf tools`, for example:

```bash
POD=$(uds zarf tools kubectl get pod -n retroarch -l app.kubernetes.io/name=retroarch -o jsonpath='{.items[0].metadata.name}')
uds zarf tools kubectl cp "./game.gba" "retroarch/${POD}:/config/roms/gba/game.gba"
```

ROMs persist across pod restarts and redeploys because they are stored on the PVC. Increase `RETROARCH_STORAGE_SIZE` at deploy time if your library is large.

### Install emulator cores

The image ships with core **metadata** (`.info` files) but not the core binaries. Install cores before loading games.

**Connected cluster (easiest):** in the RetroArch web UI:

1. **Main Menu → Online Updater → Core Downloader**
2. Install the cores you need (e.g. **Nintendo - Game Boy Advance (mGBA)**, **Nintendo - Game Boy / Color (Gambatte)**)

**Airgapped cluster:** download cores on a connected machine, then copy them into the pod:

```bash
# Example: mGBA for amd64 Linux (match your cluster architecture)
curl -sL "https://buildbot.libretro.com/nightly/linux/x86_64/latest/mgba_libretro.so.zip" -o /tmp/mgba.zip
unzip -qo /tmp/mgba.zip -d /tmp

POD=$(kubectl get pod -n retroarch -l app.kubernetes.io/name=retroarch -o jsonpath='{.items[0].metadata.name}')
kubectl cp /tmp/mgba_libretro.so "retroarch/${POD}:/config/.config/retroarch/cores/mgba_libretro.so"
kubectl exec -n retroarch deploy/retroarch -- chown abc:abc /config/.config/retroarch/cores/mgba_libretro.so
```

Restart RetroArch after adding cores (rollout restart or quit and relaunch from the desktop):

```bash
kubectl rollout restart deployment/retroarch -n retroarch
```

### Point the file browser at your ROMs

In the RetroArch UI: **Settings → Directory → File Browser** → set to `/config/roms`, then **Configuration → Save Current Configuration**.

Or set it once via the shell:

```bash
kubectl exec -n retroarch deploy/retroarch -- sh -c \
  "sed -i 's|^rgui_browser_directory = .*|rgui_browser_directory = \"/config/roms\"|' /config/.config/retroarch/retroarch.cfg"
```

### Load a game

- **Main Menu → Load Content → /config/roms/…** → pick a ROM
- Or **Main Menu → Playlists** after importing a directory (**Scan Directory** on a folder under `/config/roms`)

### Screenshots

While a game is running:

- Press **F8** (default screenshot hotkey), or
- **Quick Menu** (F1) → **Take Screenshot**

Screenshots are saved to `/config/.config/retroarch/screenshots/`. Copy them back to your machine:

```bash
POD=$(kubectl get pod -n retroarch -l app.kubernetes.io/name=retroarch -o jsonpath='{.items[0].metadata.name}')
mkdir -p ./screenshots
kubectl cp "retroarch/${POD}:/config/.config/retroarch/screenshots/." ./screenshots/
```

## Architecture

```text
Browser  -->  UDS/Istio gateway (TLS)  -->  Service :3000  -->  Pod (Selkies + RetroArch)
```

UDS terminates TLS at the tenant gateway and forwards plain HTTP to port 3000 inside the container. This matches the upstream Docker README guidance for reverse proxies — port 3001 (HTTPS with a self-signed cert) is not used behind UDS ingress.

The LinuxServer image also requires 1 GiB of shared memory (`/dev/shm`), a persistent `/config` volume, and `PUID`/`PGID` mapping.

## Package variables

| Variable | Default | Description |
|---|---|---|
| `DOMAIN` | `uds.dev` | Base domain for UDS ingress |
| `RETROARCH_PUID` | `1000` | File ownership user ID for `/config` |
| `RETROARCH_PGID` | `1000` | File ownership group ID for `/config` |
| `RETROARCH_TZ` | `Etc/UTC` | Container timezone |
| `RETROARCH_CUSTOM_USER` | _(empty)_ | HTTP basic auth username; omit to disable auth |
| `RETROARCH_PASSWORD` | _(empty)_ | HTTP basic auth password; omit to disable auth |
| `RETROARCH_STORAGE_SIZE` | `10Gi` | PVC size for config and saves |

## Configuration

| Change | File |
|---|---|
| Hostname | `values/upstream-values.yaml` → `uds.host` |
| Container image | `zarf.yaml` constant `RETROARCH_IMAGE` + rebuild |
| Page title | `values/upstream-values.yaml` → `retroarch.title` |
| Disable Wayland (headless clusters) | `values/upstream-values.yaml` → `retroarch.pixelfluxWayland` |
| Resource limits | `values/upstream-values.yaml` → `resources` |
| Storage size | `--set RETROARCH_STORAGE_SIZE=20Gi` at deploy |
| ROM library | Copy into `/config/roms/` after deploy — see [ROMs, cores, and screenshots](#roms-cores-and-screenshots) |

## Layout

| Path | Purpose |
|---|---|
| `zarf.yaml` | Package metadata, variables, exemptions component, Helm component |
| `chart/` | Deployment, PVC, Service, UDS `Package` CR |
| `manifests/uds-exemption.yaml` | Pepr policy exemptions for the LinuxServer s6/Selkies stack |
| `values/upstream-values.yaml` | Helm values templated with Zarf variables |
| `zarf-config.toml` | Zarf runtime config (deploy retries, connected dev mode) |
| `Makefile` | `lint`, `create`, `inspect`, `clean` targets |

## Building locally

```bash
make lint
make create
make create ARCH=arm64 PACKAGE_VERSION=0.1.0
make create RETROARCH_IMAGE=lscr.io/linuxserver/retroarch:latest
```

The resulting tarball is written to the repo root as `zarf-package-retroarch-<arch>-<version>.tar.zst`.

## Releasing

Push a semver tag to trigger the workflow:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The [Release Zarf Package](.github/workflows/release.yml) workflow builds both architectures and attaches the packages to a GitHub Release.

## Security notes

Read the [upstream security guidance](https://github.com/linuxserver/docker-retroarch#security) before exposing this service:

- By default there is no authentication. Set `RETROARCH_CUSTOM_USER` and `RETROARCH_PASSWORD` at deploy time for basic auth on trusted networks only.
- The web UI includes a terminal with passwordless sudo inside the container.
- Do not expose this to the internet without proper authentication and network controls.
- This package deploys UDS policy exemptions because the LinuxServer image uses s6-overlay and recommends `seccomp=unconfined` for GUI desktop containers. Exempted policies: `RequireNonRootUser`, `RestrictSeccomp`, `DropAllCapabilities`, and `DisallowPrivileged`.

For GPU acceleration, see the upstream README for Intel/AMD (`/dev/dri`) and NVIDIA configuration. Additional device mounts and runtime settings may require customizing the Deployment template.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Package` not Ready | `uds zarf tools kubectl describe package -n retroarch retroarch` |
| Blank page or 503 from ingress | Confirm the UDS `Package` expose port is `3000` (HTTP), not `3001` |
| Unexpected 401 Unauthorized | Auth env vars are omitted when empty; delete the PVC if a previous deploy wrote auth config to `/config` |
| Pod CrashLoop with `/run belongs to uid 0` | Redeploy the package; exemptions deploy before the chart and a rollout restart runs automatically |
| Stale config after redeploy | PVC persists across deploys; delete the claim to reset |
| Game won't start / "Core not found" | Install the core via **Online Updater** or copy a `.so` from [buildbot.libretro.com](https://buildbot.libretro.com); restart the pod |
| ROMs not visible in Load Content | Confirm files are under `/config/roms`, owned by `abc:abc`, and **File Browser** points to `/config/roms` |
| Screenshots not saving | Load a game first; check `/config/.config/retroarch/screenshots/` with `kubectl exec` |

## Upstream

This package wraps the LinuxServer container — it does not fork or modify RetroArch itself:

- Source: https://github.com/linuxserver/docker-retroarch
- Image: `lscr.io/linuxserver/retroarch`
- Documentation: https://docs.linuxserver.io/images/docker-retroarch

## License

This packaging repository is [MIT-licensed](LICENSE). RetroArch and the LinuxServer container are subject to their respective upstream licenses.
