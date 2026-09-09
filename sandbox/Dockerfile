# Generic development image for the sandbox; language versions are installed per repo by mise.
FROM docker.io/library/ubuntu:24.04

ARG UID=1000
ARG GID=1000
ARG USERNAME=josh

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/London \
    LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential git gh curl ca-certificates pkg-config sudo zsh tmux less vim-tiny \
      openssh-client openssh-server gnupg unzip jq ripgrep tzdata procps iproute2 \
      libssl-dev zlib1g-dev libyaml-dev libffi-dev libgmp-dev libreadline-dev libncurses-dev \
      libvips libpq-dev postgresql postgresql-client sqlite3 libsqlite3-dev libjemalloc2 rustc \
    && mkdir -p /run/sshd \
    && rm -rf /var/lib/apt/lists/*

# Node 22 from NodeSource. Paseo CLI, Claude Code, and OpenCode are npm globals installed to a system path because the home directory is bind-mounted at runtime and would hide anything installed there.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g @getpaseo/cli@0.7.2 @anthropic-ai/claude-code opencode-ai \
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

ENV HOME=/home/$USERNAME \
    CLAUDE_CONFIG_DIR=/home/$USERNAME/.claude \
    MISE_DATA_DIR=/home/$USERNAME/.local/share/mise \
    MISE_YES=1 \
    MISE_IDIOMATIC_VERSION_FILE_ENABLE_TOOLS=ruby,node,python,go \
    PATH=/home/$USERNAME/.local/bin:$PATH \
    BINDING=0.0.0.0 \
    TERM=xterm-256color \
    SHELL=/bin/zsh

COPY --chmod=755 entrypoint.sh /usr/local/bin/sandbox-entrypoint

ENTRYPOINT ["/usr/local/bin/sandbox-entrypoint"]
