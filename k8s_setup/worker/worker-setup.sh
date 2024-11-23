#!/bin/bash

# Exit on error
set -e

# Path to the join command file passed as the first argument
JOIN_COMMAND_FILE="/vagrant/join-command/kubeadm-join-command.sh"

# Ensure the file exists
if [[ ! -f "$JOIN_COMMAND_FILE" ]]; then
    echo "Error: kubeadm join command file not found at $JOIN_COMMAND_FILE."
    exit 1
fi

echo "Using kubeadm join command from $JOIN_COMMAND_FILE"

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

# Execute the kubeadm join command
echo "Joining the Kubernetes cluster..."
sudo bash "$JOIN_COMMAND_FILE"

echo "Worker node setup complete!"
