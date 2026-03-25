set -e

USER_NAME="paula"

echo "Installing Docker if missing..."

if ! command -v docker >/dev/null 2>&1; then
    dnf install -y dnf-plugins-core
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io
fi

echo "Enabling and starting Docker..."
systemctl enable docker
systemctl start docker

echo "Adding $USER_NAME to docker group..."
usermod -aG docker $USER_NAME

# Install kubectl
if ! command -v kubectl >/dev/null 2>&1; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
fi

echo "Installing Minikube if missing..."
if ! command -v minikube >/dev/null 2>&1; then
    curl -Lo /usr/local/bin/minikube \
        https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    chmod +x /usr/local/bin/minikube
fi

echo "Starting Minikube as $USER_NAME..."

# Run in fresh login shell so docker group is applied
su - $USER_NAME -c "minikube start --driver=docker"

echo "Minikube setup complete."
