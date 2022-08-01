#!/bin/sh
set -ex

K8S_VERSION=1.22.3
BYOH_VERSION=v0.2.0
BYOH_ROLE=worker
BYOH_CORE=4

#=================================================================
# perpare byoh node
#=================================================================

# /etc/hosts
echo "127.0.0.1 $(hostname)" | sudo tee -a /etc/hosts

# packages
sudo dnf install -y iproute-tc

# SELinux
sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
sudo setenforce 0

# swap
sudo sed -i '/swap/d' /etc/fstab
sudo swapoff -a

# modules
sudo cat << EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl
sudo cat << EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

# systemd-resolved
sudo systemctl start systemd-resolved.service
sudo systemctl enable systemd-resolved.service

# containerd
sudo dnf install dnf-utils -y
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y containerd.io

sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i "s/ SystemdCgroup = false/ SystemdCgroup = true/g" /etc/containerd/config.toml

sudo systemctl enable containerd
sudo systemctl restart containerd
sudo systemctl status containerd

# k8s binaries
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

sudo yum install -y kubelet-$K8S_VERSION kubeadm-$K8S_VERSION kubectl-$K8S_VERSION --disableexcludes=kubernetes

sudo dnf install yum-plugin-versionlock -y
sudo dnf versionlock kubelet kubeadm kubectl

sudo systemctl enable kubelet.service
sudo systemctl start kubelet.service
sudo systemctl status kubelet.service


#=================================================================
# install and run byoh systemd
#=================================================================
sudo curl -Lo /usr/local/bin/byoh-hostagent https://github.com/vmware-tanzu/cluster-api-provider-bringyourownhost/releases/download/$BYOH_VERSION/byoh-hostagent-linux-amd64
sudo chmod +x /usr/local/bin/byoh-hostagent

cat <<EOF | sudo tee /lib/systemd/system/byoh-hostagent.service
[Unit]
Description=byoh-hostagent: The BYOH Host Agent
Documentation=https://github.com/vmware-tanzu/cluster-api-provider-bringyourownhost/blob/main/docs/byoh_agent.md
Wants=kubelet.target
After=kubelet.target

[Service]
ExecStart=/usr/local/bin/byoh-hostagent \\
          --kubeconfig /etc/kubernetes/management-cluster.conf \\
          --label role=$BYOH_ROLE --label cores=$BYOH_CORE \\
          --skip-installation \\
          --v 20
Restart=always
StartLimitInterval=0
RestartSec=10
LimitNOFILE=65536
StandardOutput=append:/var/log/byoh-hostagent.log
StandardError=append:/var/log/byoh-hostagent-error.log

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable byoh-hostagent.service
sudo systemctl start byoh-hostagent.service
sudo systemctl status byoh-hostagent.service
