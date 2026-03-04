if ! command -v docker >/dev/null 2>&1; then
    echo "Installing Docker..."
    sudo yum install -y yum-utils conntrack
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum install -y docker-ce docker-ce-cli containerd.io
fi
 
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
 
if command -v minikube >/dev/null 2>&1; then
    echo "Minikube already installed: $(minikube version)"
else
    echo "Installing Minikube..."
    curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    chmod +x minikube
    sudo mv minikube /usr/local/bin/
fi
 
# Iniciar Minikube como usuario normal
echo "Starting Minikube..."
minikube start --driver=none
