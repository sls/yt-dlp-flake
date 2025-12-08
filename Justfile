# Justfile

# Configuration
REPO_OWNER := "yt-dlp"
REPO_NAME := "yt-dlp"
ARTIFACT_NAME := "yt-dlp"
OUT_FILE := "sources.json"

TAG_FORMAT := '{{.Repository}}:{{.Tag}}'

# list tasks
default:
    @just --list

# update, build, and load
all: update-sources build load

# update sources.json using upstream GitHub hashes
update-sources:
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Check dependencies
    for cmd in curl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: Required command '$cmd' is not installed." >&2
            exit 1
        fi
    done

    echo "Fetching latest release metadata for {{REPO_OWNER}}/{{REPO_NAME}}..."
    
    API_URL="https://api.github.com/repos/{{REPO_OWNER}}/{{REPO_NAME}}/releases/latest"
    
    # Capture HTTP code and body to handle rate limits/errors
    HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" "$API_URL")
    HTTP_BODY=$(echo "$HTTP_RESPONSE" | head -n -1)
    HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -n 1)

    if [ "$HTTP_CODE" -ne 200 ]; then
        echo "Error: GitHub API returned status $HTTP_CODE." >&2
        MSG=$(echo "$HTTP_BODY" | jq -r .message 2>/dev/null || echo "Unknown error")
        echo "Message: $MSG" >&2
        exit 1
    fi

    # Extract Version
    LATEST_TAG=$(echo "$HTTP_BODY" | jq -r '.tag_name')

    # Extract the specific asset object
    ASSET_JSON=$(echo "$HTTP_BODY" | jq -r ".assets[] | select(.name == \"{{ARTIFACT_NAME}}\")")

    if [ -z "$ASSET_JSON" ]; then
        echo "Error: Could not find artifact '{{ARTIFACT_NAME}}' in latest release." >&2
        exit 1
    fi

    DOWNLOAD_URL=$(echo "$ASSET_JSON" | jq -r '.browser_download_url')
    
    # Extract the SHA256 digest
    # GitHub returns format "sha256:abcdef..."
    # We split by ':' to get the raw hex, which Nix fetchurl accepts natively.
    DIGEST_RAW=$(echo "$ASSET_JSON" | jq -r '.digest')
    
    if [ "$DIGEST_RAW" = "null" ] || [ -z "$DIGEST_RAW" ]; then
        echo "Error: GitHub API did not provide a digest for this asset." >&2
        exit 1
    fi

    # Parse out the hex string (remove "sha256:" prefix)
    HASH_HEX=$(echo "$DIGEST_RAW" | cut -d: -f2)

    echo "Found version: $LATEST_TAG"
    echo "Upstream Hash: $HASH_HEX"

    # Generate the JSON file
    jq -n \
        --arg v "$LATEST_TAG" \
        --arg u "$DOWNLOAD_URL" \
        --arg h "$HASH_HEX" \
        '{version: $v, url: $u, hash: $h}' > "{{OUT_FILE}}"

    echo "Updated {{OUT_FILE}} successfully."

# build the image
build:
    nix build

# load into podman
load:
    podman load < result

# tag the current version as 'latest'
promote:
    #!/usr/bin/env bash
    set -euo pipefail
    VERSION=$(jq -r .version sources.json)
    echo "Promoting version $VERSION to latest..."
    podman tag localhost/yt-dlp-image:$VERSION localhost/yt-dlp-image:latest
    echo "Done. You can now run 'localhost/yt-dlp-image:latest'."

# remove all yt-dlp images EXCEPT the current version and 'latest'
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    VERSION=$(jq -r .version sources.json)
    if [[ -z "$VERSION" ]]; then echo "No version in sources.json"; exit 1; fi
    echo "clean up old yt-dlp images"

    # list all tags for this repository
    # filter out the current version
    # filter out the 'latest' tag
    # remove the rest
    podman images --format {{TAG_FORMAT}} localhost/yt-dlp-image \
      | grep -v ":$VERSION$" \
      | grep -v ":latest$" \
      | xargs -r podman rmi

# show the sorted layers in the latest image
history:
    podman history localhost/yt-dlp-image:latest | sort -h -k 5

# vim: syntax=just et ai ts=4 sw=4
