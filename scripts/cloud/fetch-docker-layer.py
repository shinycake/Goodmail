"""Download the largest Linux layer of an official Docker image: for the swift image, the toolchain itself.

Usage: python3 -I fetch-docker-layer.py <image> <tag> <amd64|arm64> <output.tar.gz>

Cloud workers can't reach download.swift.org, and they have no Docker daemon to pull with, so this speaks the registry
API directly. Docker Hub rate-limits anonymous pulls, so it tries the mirrors that carry Docker's official images
first, each a few times, and Docker Hub last. Layers are addressed by digest, so every registry serves the same bytes,
and the layer is checked against its digest before the script exits successfully.
"""

import hashlib
import json
import sys
import time
import urllib.request
from dataclasses import dataclass
from typing import Callable, Optional

ACCEPT = ",".join(
    [
        "application/vnd.oci.image.index.v1+json",
        "application/vnd.docker.distribution.manifest.list.v2+json",
        "application/vnd.oci.image.manifest.v1+json",
        "application/vnd.docker.distribution.manifest.v2+json",
    ]
)
ATTEMPTS = 3


@dataclass
class Registry:
    name: str
    base: str  # the registry's /v2 endpoint
    repository: Callable[[str], str]  # where it keeps an official image such as "swift"
    token_url: Optional[Callable[[str], str]]  # anonymous pull token, for registries that need one


REGISTRIES = [
    Registry("mirror.gcr.io", "https://mirror.gcr.io/v2", lambda image: f"library/{image}", None),
    Registry(
        "public.ecr.aws",
        "https://public.ecr.aws/v2",
        lambda image: f"docker/library/{image}",
        lambda repository: f"https://public.ecr.aws/token/?scope=repository:{repository}:pull",
    ),
    Registry(
        "Docker Hub",
        "https://registry-1.docker.io/v2",
        lambda image: f"library/{image}",
        lambda repository: f"https://auth.docker.io/token?service=registry.docker.io&scope=repository:{repository}:pull",
    ),
]


def fetch(registry: Registry, image: str, tag: str, architecture: str, output: str) -> None:
    repository = registry.repository(image)
    headers = {"Accept": ACCEPT}
    if registry.token_url:
        token = json.load(urllib.request.urlopen(registry.token_url(repository), timeout=60))["token"]
        headers["Authorization"] = f"Bearer {token}"

    def get(path: str):
        request = urllib.request.Request(f"{registry.base}/{repository}/{path}", headers=headers)
        return urllib.request.urlopen(request, timeout=120)

    manifest = json.load(get(f"manifests/{tag}"))
    if "manifests" in manifest:  # a multi-platform index
        platform = next(
            entry["digest"]
            for entry in manifest["manifests"]
            if entry["platform"]["os"] == "linux" and entry["platform"]["architecture"] == architecture
        )
        manifest = json.load(get(f"manifests/{platform}"))
    layer = max(manifest["layers"], key=lambda entry: entry["size"])

    sha = hashlib.sha256()
    with get(f"blobs/{layer['digest']}") as response, open(output, "wb") as file:
        while chunk := response.read(1 << 20):
            sha.update(chunk)
            file.write(chunk)
    if f"sha256:{sha.hexdigest()}" != layer["digest"]:
        raise ValueError(f"layer {layer['digest']} failed its digest check")


def main(image: str, tag: str, architecture: str, output: str) -> None:
    failures = []
    for registry in REGISTRIES:
        for attempt in range(1, ATTEMPTS + 1):
            try:
                fetch(registry, image, tag, architecture, output)
                print(f"{image}:{tag} ({architecture}) from {registry.name}")
                return
            except Exception as error:  # network errors, rate limits (HTTP 429), digest mismatches: try again
                failures.append(f"{registry.name} attempt {attempt}: {error}")
                print(failures[-1], file=sys.stderr)
                if attempt < ATTEMPTS:
                    time.sleep(5 * attempt)
    sys.exit(f"Couldn't download {image}:{tag} from any registry:\n" + "\n".join(failures))


if __name__ == "__main__":
    main(*sys.argv[1:])
