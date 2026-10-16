# Generic development image for the sandbox; language versions are installed per repo by mise.
FROM docker.io/library/ubuntu:24.04

ARG UID=1000
ARG GID=1000
ARG USERNAME=josh

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/London \
    LANG=C.UTF-8

# No Rust toolchain from apt, on purpose. The toolchain lives in the persistent home, and a
# second compiler in the image does active harm: a cargo from one version paired with a rustc
# from the other fails the build with an error that never mentions versions (see
# parallel-builds.md). Nothing else in this image depends on the apt package.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential git gh curl ca-certificates pkg-config sudo zsh tmux less vim-tiny \
      openssh-client openssh-server gnupg unzip jq ripgrep tzdata procps iproute2 \
      libssl-dev zlib1g-dev libyaml-dev libffi-dev libgmp-dev libreadline-dev libncurses-dev \
      libvips libpq-dev postgresql postgresql-client sqlite3 libsqlite3-dev libjemalloc2 \
      watchman \
    && mkdir -p /run/sshd \
    && rm -rf /var/lib/apt/lists/*

ARG SCCACHE_VERSION=0.18.0
ARG SCCACHE_ARCH=x86_64-unknown-linux-musl
ARG SCCACHE_SHA256=45f1447fbe231e3037bde351ef70677dd212216c8d62ae7ca409fecc4d6acc89

# A compile cache shared by every worktree, so parallel agents stop rebuilding the same
# dependency tree from cold. It goes in the image rather than the persistent home because the
# wrapper is a hard dependency for every cargo command in the container, and a home that is
# fresh or predates the install must not be able to break all of them. The entrypoint checks
# for the binary anyway and leaves the wrapper unset when it is missing, so the failure mode
# is a slow build rather than a broken one. Built for x86_64: change SCCACHE_ARCH for arm64.
RUN curl -fsSL -o /tmp/sccache.tar.gz \
      "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}.tar.gz" \
    && echo "${SCCACHE_SHA256}  /tmp/sccache.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/sccache.tar.gz -C /tmp \
    && install -m 0755 "/tmp/sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}/sccache" /usr/local/bin/sccache \
    && rm -rf /tmp/sccache.tar.gz "/tmp/sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}" \
    && sccache --version

# Ubuntu's default pg_hba.conf authenticates local connections with peer, so a
# Rails app whose database.yml names `postgres` cannot connect as the josh user.
# The sandbox is a single-user dev container reachable only over the host's
# loopback, so local and loopback connections trust any role.
RUN printf 'local all all trust\nhost all all 127.0.0.1/32 trust\nhost all all ::1/128 trust\n' \
      | tee /etc/postgresql/*/main/pg_hba.conf >/dev/null

# Node 22 from NodeSource, for the npm globals below. They sit on a system path because the home is bind-mounted at runtime and would hide anything installed there. The Paseo CLI baked in here is the fallback for the copy ai.sh installs into the persistent home. Claude Code also lives in the persistent home: ai.sh runs its native installer on first start, and it self-updates.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g @getpaseo/cli@latest \
    && chown -R "$UID:$GID" /usr/lib/node_modules/@getpaseo \
    && rm -rf /var/lib/apt/lists/*

# Playwright with Chromium so agents can screenshot the apps they build. Browsers
# go to /opt because the runtime bind mount over the home directory hides the
# default ~/.cache/ms-playwright location. --with-deps pulls in the ~30 apt
# libraries headless Chromium links against.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN npm install -g playwright \
    && playwright install --with-deps chromium \
    && chmod -R a+rX /opt/ms-playwright \
    && rm -rf /var/lib/apt/lists/*

# ubuntu:24.04 ships an `ubuntu` user at uid 1000. Remove it so the container
# user can take the same uid as josh on the host and bind mounts keep ownership.
RUN userdel -r ubuntu 2>/dev/null || true \
    && groupadd -g "$GID" "$USERNAME" \
    && useradd -m -u "$UID" -g "$GID" -s /bin/zsh "$USERNAME" \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
    && chmod 0440 "/etc/sudoers.d/$USERNAME"

# mise binary lives in the image; its installs live in the bind-mounted home.
RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh

COPY sshd_config /etc/ssh/sandbox_sshd_config

USER $USERNAME
WORKDIR /home/$USERNAME

# Every process the entrypoint spawns inherits this PATH, including agent harnesses that
# freeze it into their own shell. Shims go last so a mise node stays behind the system node Paseo runs on.
# The Rust toolchain's bin directory sits ahead of the system ones, so cargo and rustc are the
# pair from the persistent home rather than the system rustc the image no longer installs.
ENV HOME=/home/$USERNAME \
    CLAUDE_CONFIG_DIR=/home/$USERNAME/.claude \
    MISE_DATA_DIR=/home/$USERNAME/.local/share/mise \
    MISE_YES=1 \
    MISE_IDIOMATIC_VERSION_FILE_ENABLE_TOOLS=ruby,node,python,go \
    PATH=/home/$USERNAME/.local/bin:/home/$USERNAME/.cargo/bin:$PATH:/home/$USERNAME/.local/share/mise/shims \
    BINDING=0.0.0.0 \
    TERM=xterm-256color \
    SHELL=/bin/zsh

COPY --chmod=755 entrypoint.sh /usr/local/bin/sandbox-entrypoint

ENTRYPOINT ["/usr/local/bin/sandbox-entrypoint"]
