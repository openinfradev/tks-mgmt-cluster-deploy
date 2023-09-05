#!/bin/bash

# uninstall script for a byoh host
# copy this script to each host and run!

if [ -z "$1" ]; then
    echo "usage: $0 <bundle path>"
    echo '- bundle path example /var/lib/byoh/bundles/harbor-cicd.taco-cat.xyz/cluster_api_provider_bringyourownhost/byoh-bundle-rocky_linux_8.7_x86-64_k8s\:v1.25.11/'
    exit 1
fi

BUNDLE_PATH=$1

## disabling byoh-hostagent service
sudo systemctl stop byoh-hostagent && sudo systemctl disable byoh-hostagent && sudo systemctl daemon-reload

## disabling kubelet service
sudo systemctl stop kubelet && sudo systemctl disable kubelet && sudo systemctl daemon-reload

## disabling containerd service
sudo systemctl stop containerd && sudo systemctl disable containerd && sudo systemctl daemon-reload

## removing containerd configurations and cni plugins
sudo rm -rf /opt/cni/ && sudo rm -rf /opt/containerd/ &&  sudo tar tf "$BUNDLE_PATH/containerd.tar" | xargs -n 1 echo '/' | sed 's/ //g'  | grep -e '[^/]$' | xargs sudo rm -f

## removing packages
for pkg in kubeadm kubelet kubectl kubernetes-cni cri-tools; do
        sudo yum remove $pkg -y
done

## removing os configuration
sudo tar tf "$BUNDLE_PATH/conf.tar" | xargs -n 1 echo '/etc/sysctl.d/' | sed 's/ //g' | grep -e "[^/]$" | xargs sudo rm -f

## remove kernal modules
sudo modprobe -rq overlay && modprobe -r br_netfilter

## enable firewall
echo "Starting and enabling Firewalld."
sudo systemctl start firewalld || true
sudo systemctl enable firewalld || true

## enable selinux
sudo setenforce 1
sudo sed -i 's/^SELINUX=permissive$/SELINUX=enforcing/' /etc/selinux/config

## enable swap
sudo swapon -a && sudo sed -ri '/\sswap\s/s/^#?//' /etc/fstab

sudo rm -rf $BUNDLE_PATH
