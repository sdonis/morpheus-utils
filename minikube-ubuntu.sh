export DEBIAN_FRONTEND=noninteractive

# Detectar usuario real (si no existe, usar ubuntu)
REAL_USER=${SUDO_USER:-ubuntu}

# -------------------------
# Install Docker if missing
# -------------------------
if ! command -v docker >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release conntrack

    mkdir -p /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io
fi

systemctl enable docker
systemctl start docker

# Añadir usuario al grupo docker (sin romper si ya está)
if id "$REAL_USER" &>/dev/null; then
    usermod -aG docker "$REAL_USER"
fi

# -------------------------
# Install Minikube if missing
# -------------------------
if ! command -v minikube >/dev/null 2>&1; then
    curl -Lo /usr/local/bin/minikube \
        https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    chmod +x /usr/local/bin/minikube
fi

# -------------------------
# Start Minikube (SIN newgrp)
# -------------------------
sudo -u "$REAL_USER" minikube start \
    --driver=docker \
    --cpus=4 \
    --memory=16384
