
terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.6.17"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

data "coder_provisioner" "me" {
}

provider "docker" {
}

data "coder_workspace" "me" {
}

data "coder_parameter" "dotfiles_uri" {
  name        = "What dotfiles repo would you like to use for your workspace?"
  description = "Dotfiles repo URI (optional)"
  default     = "https://github.com/ghuntley/dotfiles-coder"
  type        = "string"
  mutable     = true
}


resource "coder_agent" "main" {
  arch                   = data.coder_provisioner.me.arch
  os                     = "linux"
  env                    = { "DOTFILES_URI" = data.coder_parameter.dotfiles_uri.value != "" ? data.coder_parameter.dotfiles_uri.value : null }
  login_before_ready     = false
  startup_script_timeout = 180
  startup_script         = <<-EOT
    set -e
    
    sudo apt-get update && apt-get update && apt-get install --yes \
      apt-transport-https \
      apt-utils \
      bash \
      bash-completion \
      bat \
      bats \
      bind9-dnsutils \
      build-essential \
      ca-certificates \
      cmake \
      crypto-policies \
      curl \
      fd-find \
      file \
      git \
      gnupg \
      graphviz \
      htop \
      httpie \
      inetutils-tools \
      iproute2 \
      iputils-ping \
      iputils-tracepath \
      jq \
      language-pack-en \
      less \
      lsb-release \
      man \
      meld \
      net-tools \
      openssh-server \
      openssl \
      pkg-config \
      python3 \
      python3-pip \
      rsync \
      shellcheck \
      strace \
      stow \
      sudo \
      tcptraceroute \
      termshark \
      tmux \
      traceroute \
      vim \
      wget \
      xauth \
      zip \
      ncdu \
      asciinema \
      zsh \
      neovim \
      fish \
      unzip \
      zstd && \
      # Configure FIPS-compliant policies
    	update-crypto-policies --set FIPS

    # Install starship
    curl -sS https://starship.rs/install.sh | sh -s -- --yes

    # install and start code-server
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.8.3
    /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &

    if [ -n "$DOTFILES_URI" ]; then
      echo "Installing dotfiles from $DOTFILES_URI"
      coder dotfiles "$DOTFILES_URI" --yes
    fi

    # https://github.com/Frederic-Boulanger-UPS/docker-ubuntu-novnc/tree/master
    export RESOLUTION=1920x1080
    /startup.sh >/tmp/novnc.log 2>&1 &

  EOT
}

resource "coder_app" "novnc" {
  agent_id     = coder_agent.main.id
  slug         = "novnc"
  display_name = "noVNC"
  url          = "http://localhost:80/"
  icon         = ""
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://127.0.0.1:6079/api/health"
    interval  = 3
    threshold = 10
  }

}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  url          = "http://localhost:13337/?folder=/home/ghuntley"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }
}

data "coder_parameter" "container_enable_dind" {
  name        = "Enable Docker in Docker in Docker?"
  description = "This is insecure"
  default     = "false"
  type        = "bool"
  mutable     = true
  option {
    name  = "false"
    value = false
  }
  option {
    name  = "true"
    value = true
  }
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace.me.owner
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace.me.owner_id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_volume" "nix_volume" {
  name = "coder-${data.coder_workspace.me.id}-nix"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace.me.owner
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace.me.owner_id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

data "docker_registry_image" "coder_image" {
  name = "fredblgr/ubuntu-novnc:20.04"
}

resource "docker_image" "coder_image" {
  name          = data.docker_registry_image.coder_image.name
  pull_triggers = [data.docker_registry_image.coder_image.sha256_digest]

  # Keep alive for other workspaces to use upon deletion
  keep_locally = true
}

resource "docker_container" "workspace" {

  # Use the Sysbox container runtime
  # runtime = "sysbox-runc"

  # enable docker-in-docker-in-docker nb: reduces security 
  privileged = data.coder_parameter.container_enable_dind.value
  mounts {
    source = data.coder_parameter.container_enable_dind.value ? "/var/run/docker.sock" : "/dev/null"
    target = "/var/run/docker.sock"
    type = "bind"
  }

  count = data.coder_workspace.me.start_count
  image = data.docker_registry_image.coder_image.name
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.me.name
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/ghuntley/"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  volumes {
    container_path = "/nix/"
    volume_name    = docker_volume.nix_volume.name
    read_only      = false
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace.me.owner
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace.me.owner_id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}

resource "coder_metadata" "container_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id

  item {
    key   = "image"
    value = data.docker_registry_image.coder_image.name
  }
}
