#!/bin/bash

# Exit on error
set -e

# Update the system
echo "Updating the system..."
sudo apt-get update -y && sudo apt-get upgrade -y

# Enable IP forwarding
echo "Enabling IP forwarding..."
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward
sudo sysctl -w net.ipv4.ip_forward=1

# Persist the setting across reboots
echo "Persisting IP forwarding settings..."
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# Install required packages
echo "Installing required packages..."
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Add Kubernetes APT repository
echo "Adding Kubernetes APT repository..."
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install kubeadm, kubelet, and kubectl
echo "Installing kubeadm, kubelet, and kubectl..."
sudo apt-get update -y
sudo apt-get install -y kubeadm kubelet kubectl
sudo apt-mark hold kubeadm kubelet kubectl
sudo systemctl enable --now kubelet

# Disable swap (required for Kubernetes)
echo "Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/' /etc/fstab

# Install containerd runtime
echo "Installing containerd..."
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Adjust containerd configuration for Kubernetes
echo "Configuring containerd..."
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Load necessary kernel modules
echo "Loading kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF
sudo modprobe br_netfilter

# Set sysctl parameters
echo "Setting sysctl parameters..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sudo sysctl --system

# Initialize the Kubernetes master node
echo "Initializing Kubernetes master node..."
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --cri-socket unix:///run/containerd/containerd.sock

# Set up kubeconfig for the current user
echo "Setting up kubeconfig..."
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Deploy a pod network (e.g., Calico)
echo "Deploying Calico network plugin..."
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Generate join command and save to a file
echo "Saving kubeadm join command..."
JOIN_COMMAND=$(kubeadm token create --print-join-command)
echo "${JOIN_COMMAND}" | sudo tee /vagrant/join-command/kubeadm-join-command.sh
sudo chmod +x /vagrant/join-command/kubeadm-join-command.sh

echo "Kubernetes master node setup is complete! Join command saved in /vagrant/join-command/kubeadm-join-command.sh."
