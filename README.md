# Nix-based yt-dlp OCI Image

A minimal, bit-for-bit reproducible, and secure OCI container image for `yt-dlp`.

## Motivation

Recently, `yt-dlp` added a requirement for a Javascript runtime (like Deno) to handle complex extractors. While necessary for functionality, installing a general-purpose JS runtime on a host machine to execute code downloaded from arbitrary third-party websites introduces a new class of security risks.

This project solves that by wrapping `yt-dlp` and `deno` in a minimal, highly isolated OCI container. 

### Highlights
* **Isolated Runtime:** The Javascript runtime lives and dies inside the container. It has no access to the host filesystem beyond the specific download directory.
* **Minimal Footprint:** Uses Nix to build a layered image containing *only* the necessary closures.
    * **Size:** ~600MB (compared to ~1GB for standard distro-based images with these dependencies).
    * Uses `ffmpeg-headless` and a custom Python 3 closure.
* **Reproducible:** Built using Nix Flakes. The build is declarative and relies on pinned SHA256 hashes from GitHub Releases.
* **Secure Supply Chain:** The build process verifies the upstream SHA256 digest provided by the `yt-dlp` GitHub Release API before building.

## Prerequisites

* **Nix** (with flakes enabled)
* **Podman** (recommended) or Docker
* **Just** (command runner)
* **jq** & **curl** (for fetching update metadata)

## Usage

### Build the Image
The included `Justfile` handles fetching the latest upstream hash, updating the lockfile, and building the image.

```
Available recipes:
    all            # update, build, and load
    build          # build the image
    clean          # remove all yt-dlp images EXCEPT the current version and 'latest'
    default        # list tasks
    history        # show the sorted layers in the latest image
    load           # load into podman
    promote        # tag the current version as 'latest'
    update-sources # update sources.json using upstream GitHub hashes
```

### Run the image
As an example, this shell function will allow use of the image as if it were a local program.
Add this to your `.bashrc` or `.zshrc`:

```bash
yt-dlp() {
    podman run \
        --volume "$PWD:/downloads:Z" \
        --rm \
        localhost/yt-dlp-image:latest \
        "$@"
}

You can test new versions by running them directly (e.g. `localhost/yt-dlp-image:2025-12-08`) before promoting them to `latest` to for your scripts, functions, aliases, etc.

### Podman container policy

If your podman container policy is default reject, you'll want to add something like the following to your podman `policy.json` in the list of transports:
```json
    "docker-archive": {
      "": [
        {
          "type": "insecureAcceptAnything"
        }
      ]
    },
    "oci-archive": {
      "": [
        {
          "type": "insecureAcceptAnything"
        }
      ]
    }
```
This will allow you to `podman load` the new image for local use.

### Created timestamp

We don't set this so that the identical image can be built again from the same sources. Instead, it's left at the Unix Epoch, 1970-01-01. Don't worry about podman saying your image was created decades ago 😉

## Maintenance

To update to the latest version of yt-dlp:
```bash
# Fetch latest release metadata, build, and load
just all

# Verify it works (<tag> is the tag of the release you just downloaded, `podman image ls` will show the images
podman run --volume "$PWD:/downloads:Z" --rm yt-dlp-image:<tag> $*

# Promote the new build to 'latest'
just promote

# Cleanup old layers/images
just clean
```
