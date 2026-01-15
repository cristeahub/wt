FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install base system packages
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    vim \
    htop \
    wget \
    unzip \
    jq \
    ripgrep \
    fd-find \
    software-properties-common \
    sudo \
    ca-certificates \
    gnupg \
    iproute2 \
    socat \
    && rm -rf /var/lib/apt/lists/*

# Install PostgreSQL and PostGIS
RUN apt-get update && apt-get install -y \
    postgresql \
    postgresql-contrib \
    postgresql-16-postgis-3 \
    postgis \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Configure PostgreSQL to allow local connections without password for dev user
RUN service postgresql start && \
    su - postgres -c "psql -c \"CREATE USER dev WITH SUPERUSER CREATEDB CREATEROLE PASSWORD 'dev';\"" && \
    su - postgres -c "createdb dev -O dev" && \
    su - postgres -c "psql -d dev -c \"CREATE EXTENSION postgis;\"" && \
    service postgresql stop

# Trust authentication for local connections (dev container only — no password required)
RUN echo "local all all trust" > /etc/postgresql/16/main/pg_hba.conf && \
    echo "host all all 127.0.0.1/32 trust" >> /etc/postgresql/16/main/pg_hba.conf && \
    echo "host all all ::1/128 trust" >> /etc/postgresql/16/main/pg_hba.conf

# Install Python (multiple versions)
RUN add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && apt-get install -y \
    python3.11 python3.11-venv python3.11-dev \
    python3.12 python3.12-venv python3.12-dev \
    python3.13 python3.13-venv python3.13-dev \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.13 1

# Create non-root user
RUN useradd -m -s /bin/bash -u 1001 dev && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Allow dev user to control PostgreSQL (directory created in entrypoint.sh)
# /var/run is tmpfs, so directory must be created at runtime

USER dev
WORKDIR /home/dev

# Install Node.js via nvm
ENV NVM_DIR=/home/dev/.nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash && \
    . "$NVM_DIR/nvm.sh" && \
    nvm install --lts && \
    nvm use --lts && \
    npm install -g yarn pnpm

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/dev/.cargo/bin:${PATH}"

# Install Go (detect architecture)
USER root
ARG TARGETARCH
RUN GOARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "amd64") && \
    curl -LO "https://go.dev/dl/go1.23.3.linux-${GOARCH}.tar.gz" && \
    tar -C /usr/local -xzf "go1.23.3.linux-${GOARCH}.tar.gz" && \
    rm "go1.23.3.linux-${GOARCH}.tar.gz"
USER dev
ENV PATH="/usr/local/go/bin:${PATH}"

# Install uv (Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/home/dev/.local/bin:${PATH}"

# Configure shell
RUN echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc && \
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc && \
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc && \
    echo 'export PATH="/usr/local/go/bin:$PATH"' >> ~/.bashrc && \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && \
    echo 'export PATH="$HOME/.claude/bin:$PATH"' >> ~/.bashrc && \
    echo 'alias pg-start="sudo service postgresql start"' >> ~/.bashrc && \
    echo 'alias pg-stop="sudo service postgresql stop"' >> ~/.bashrc && \
    echo 'alias pg-status="sudo service postgresql status"' >> ~/.bashrc

WORKDIR /workspace

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
USER root
RUN chmod +x /usr/local/bin/entrypoint.sh
USER dev

# Install Claude CLI last (ARG busts cache to force update on rebuild)
ARG CLAUDE_CACHE_BUST=1
RUN curl -fsSL https://claude.ai/install.sh | bash || true
ENV PATH="/home/dev/.claude/bin:${PATH}"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
