FROM ubuntu:jammy

# Add a user `ghuntley` so that you're not developing as the `root` user
RUN useradd ghuntley \
    --create-home \
    --shell=/bin/bash \
    --uid=1000 \
    --user-group && \
	mkdir -p /etc/sudoers.d && \
    echo "ghuntley ALL=(ALL) NOPASSWD:ALL" >>/etc/sudoers.d/nopasswd && \
	groupadd docker && \
	usermod -aG docker ghuntley

# Install packages from apt repositories
ARG DEBIAN_FRONTEND="noninteractive"

# Install Docker 
RUN apt-get update && apt-get install --yes \
	ca-certificates curl gnupg lsb-release software-properties-common && \
    mkdir -m 0755 -p /etc/apt/keyrings && \
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
  	apt-get update && apt-get install --yes docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && \
	# Delete package cache to avoid consuming space in layer
	apt-get clean

RUN apt-get update && apt-get install --yes \
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
	# Delete package cache to avoid consuming space in layer
	apt-get clean && \
	# Configure FIPS-compliant policies
	update-crypto-policies --set FIPS

# Install starship
RUN curl -sS https://starship.rs/install.sh | sh -s -- --yes

# Install Lazygit
# See https://github.com/jesseduffield/lazygit#ubuntu
RUN LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep '"tag_name":' |  sed -E 's/.*"v*([^"]+)".*/\1/') && \
	curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" && \
	tar xf lazygit.tar.gz -C /usr/local/bin lazygit

# Adjust OpenSSH config
RUN echo "PermitUserEnvironment yes" >>/etc/ssh/sshd_config && \
	echo "X11Forwarding yes" >>/etc/ssh/sshd_config && \
	echo "X11UseLocalhost no" >>/etc/ssh/sshd_config

# Install Nix
RUN addgroup --system nixbld \
  && adduser ghuntley nixbld \
  && for i in $(seq 1 30); do useradd -ms /bin/bash nixbld$i &&  adduser nixbld$i nixbld; done \
  && mkdir -m 0755 /nix && chown ghuntley /nix \
  && mkdir -p /etc/nix && echo 'sandbox = false' > /etc/nix/nix.conf

CMD /bin/bash -l
USER ghuntley
ENV USER ghuntley
WORKDIR /home/ghuntley

RUN touch .bash_profile \
 && curl https://nixos.org/releases/nix/nix-2.9.2/install | sh

RUN echo '. /home/ghuntley/.nix-profile/etc/profile.d/nix.sh' >> /home/ghuntley/.bashrc
RUN mkdir -p /home/ghuntley/.config/nixpkgs && echo '{ allowUnfree = true; }' >> /home/ghuntley/.config/nixpkgs/config.nix

# Install cachix
RUN . /home/ghuntley/.nix-profile/etc/profile.d/nix.sh \
  && nix-env -iA cachix -f https://cachix.org/api/v1/install \
  && cachix use cachix

# Install direnv
RUN . /home/ghuntley/.nix-profile/etc/profile.d/nix.sh \
  && nix-env -i direnv \
  && direnv hook bash >> /home/ghuntley/.bashrc

# Install devenv
RUN . /home/ghuntley/.nix-profile/etc/profile.d/nix.sh \
	nix-env -iA cachix -f https://cachix.org/api/v1/install && \
    cachix use devenv && \
    nix-env -if https://github.com/cachix/devenv/tarball/latest

# Run as
USER ghuntley
