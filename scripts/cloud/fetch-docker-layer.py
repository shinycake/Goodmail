"""Download the largest Linux layer of a Docker Hub image: for the official swift image, the toolchain itself.

Usage: python3 -I fetch-docker-layer.py <repository> <tag> <amd64|arm64> <output.tar.gz>

Cloud workers can't reach download.swift.org, but they can reach Docker Hub, and they have no Docker daemon to pull
with. The layer is checked against the digest in the image manifest before the script exits successfully.
"""

import hashlib
import json
import sys
import urllib.request

REGISTRY = "https://registry-1.docker.io/v2"
ACCEPT = ",".join(
    [
        "application/vnd.oci.image.index.v1+json",
        "application/vnd.docker.distribution.manifest.list.v2+json",
        "application/vnd.oci.image.manifest.v1+json",
        "application/vnd.docker.distribution.manifest.v2+json",
    ]
)


def main(repository: str, tag: str, architecture: str, output: str) -> None:
    token_url = f"https://auth.docker.io/token?service=registry.docker.io&scope=repository:{repository}:pull"
    token = json.load(urllib.request.urlopen(token_url))["token"]

    def get(path: str):
        headers = {"Authorization": f"Bearer {token}", "Accept": ACCEPT}
        return urllib.request.urlopen(urllib.request.Request(f"{REGISTRY}/{repository}/{path}", headers=headers))

    manifest = json.load(get(f"manifests/{tag}"))
    if "manifests" in manifest:  # a multi-platform index
        image = next(
            entry["digest"]
            for entry in manifest["manifests"]
            if entry["platform"]["os"] == "linux" and entry["platform"]["architecture"] == architecture
        )
        manifest = json.load(get(f"manifests/{image}"))
    layer = max(manifest["layers"], key=lambda entry: entry["size"])

    sha = hashlib.sha256()
    with get(f"blobs/{layer['digest']}") as response, open(output, "wb") as file:
        while chunk := response.read(1 << 20):
            sha.update(chunk)
            file.write(chunk)
    if f"sha256:{sha.hexdigest()}" != layer["digest"]:
        sys.exit(f"{repository}:{tag}: layer {layer['digest']} failed its digest check")


if __name__ == "__main__":
    main(*sys.argv[1:])
