# Reproducible builds

We want to improve the transparency and auditability of our build artifacts, and
a way to achieve this is via reproducible builds. For a broader understanding of
what reproducible builds entail, check out https://reproducible-builds.org/.

Our build artifacts consist of:
* Container images (`amd64` and `arm64` architectures)
* macOS installers (for Intel and Apple Silicon CPUs)
* Windows installer
* Fedora packages (for regular Fedora distros and Qubes)
* Debian packages (for Debian and Ubuntu)

As of writing this, none of the above artifacts are reproducible. For this
reason, we purposefully build them in machines owned by FPF, since we can't
trust third-party servers. A security hole in GitHub, or
in our CI pipeline (check out the
[Ultralytics cryptominer saga](https://github.com/ultralytics/ultralytics/issues/18027)),
may allow attackers to plant a malicious artifact with no detection.

Still, building our artifacts in private is not ideal. Third parties cannot
easily audit if our artifacts have been built correctly or if they have been
tampered with. For instance, our Apple Silicon container image builds PyMuPDF
from source, and while the PyPI source package is hashed, the produced output
does not have a known hash. So, it's not easy to verify it's been built
correctly (read also the seminal
["Reflections on Trusting Trust"](https://www.cs.cmu.edu/~rdriley/487/papers/Thompson_1984_ReflectionsonTrustingTrust.pdf)
lecture by Ken Thompson on that subject).

In order to make our builds auditable and allow building artifacts in
third-party servers safely, we want to make each artifact build reproducible. In
the following sections, we'll lay down the plan to do so for each artifact type.

## Container image

### Current limitations

Our container image is currently not reproducible for the following main
reasons:

* We build PyMuPDF from source, since it's not available in Alpine Linux. The
  result of this build is not reproducible. Note that PyMuPDF wheels are
  available from PyPI, but there are no ARM wheels for the musl libc platforms.
* Alpine Linux does not have a way to pin packages and their dependencies, and
  does not retain old packages. There's a
  [workaround](https://github.com/reproducible-containers/repro-pkg-cache)
  to download the required packages and store them elsewhere, but then the
  cached package downloads cannot be easily audited.

## Proposed implementation

We can take advantage of the
[Debian snapshot archives](https://snapshot.debian.org/)
and pin our packages by specifying a date. There's already
[prior art](https://github.com/reproducible-containers/repro-sources-list.sh/)
for that, thanks to the incredible work of @AkihiroSuda on
[reproducible containers](https://github.com/reproducible-containers).
As for PyMuPDF, it is available from the Debian repos, so we won't have to build
it from source.

Here are a few other obstacles that we need to overcome:
* We currently download the
  [latest gVisor version](https://gvisor.dev/docs/user_guide/install/#latest-release)
  from a GCS bucket. Now that we have switched to Debian, we can take advantage
  of their
  [timestamped APT repos](https://gvisor.dev/docs/user_guide/install/#specific-release)
  and download specific releases from those. An extra benefit is that such
  releases are signed with their APT key.
* We can no longer update the packages in the container image by rebuilding it.
  We have to bump the dates in the Dockerfile first, which is a minor hassle,
  but much more declarative.
* The `repro-source-list-.sh` script uses the release date of the container
  image. However, the Debian image is not updated daily (see
  [newest tags](https://hub.docker.com/_/debian/tags)
  in DockerHub). So, if we want to ship an emergency release, we have to
  circumvent this limitation. A simple way is to trick the script by bumping the
  date of the `/etc/apt/sources.list.d/debian.sources` and
  `/etc/apt/sources.list` files.
* While we talk about image reproducibility, we can't actually achieve the exact
  same SHA-256 hash for two different image builds. That's because the file
  timestamps in the image layers will differ, depending on when the build took
  place. The rest of the image though (file contents, permissions, manifest)
  should be byte-for-byte the same. A simple way to check this is with the
  [`diffoci`](https://github.com/reproducible-containers/diffoci) tool, and
  specifically this invocation:

  ```
  ./diffoci diff podman://<new_image_tag> podman://<old_image_tag> \
      --ignore-timestamps --ignore-image-name --verbose
  ```
