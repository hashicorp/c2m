#!/bin/bash
# setup script for Debian Stretch Linux 10. Assumes that Packer has placed
# build-time config files at /tmp/linux

set -exv

# Will be overwritten at test time with the version specified
NOMADVERSION="1.0.0-beta3.2"
CONSULVERSION=1.8.4

NOMAD_PLUGIN_DIR=/opt/nomad/plugins/

mkdir_for_root() {
    sudo mkdir -p "$1"
    sudo chmod 755 "$1"
}

# Disable interactive apt prompts
export DEBIAN_FRONTEND=noninteractive
echo 'debconf debconf/frontend select Noninteractive' | sudo debconf-set-selections

mkdir_for_root /opt

# Dependencies
sudo apt-get update
sudo apt-get install -y \
     software-properties-common \
     sysstat htop \
     dnsmasq unzip tree jq curl tmux awscli nfs-common \
     apt-transport-https ca-certificates gnupg2 gnupg-agent

echo "Install Datadog"
sudo sh -c "echo 'deb https://apt.datadoghq.com/ stable 7' > /etc/apt/sources.list.d/datadog.list"
sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 A2923DFF56EDA6E76E55E492D3A80E30382E94DE
sudo apt-get update
sudo apt-get install datadog-agent

echo "Install SSM"
mkdir_for_root /tmp/ssm
sudo wget -O /tmp/ssm/amazon-ssm-agent.deb https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
sudo dpkg -i /tmp/ssm/amazon-ssm-agent.deb
sudo systemctl enable amazon-ssm-agent

echo "Install Consul"
curl -fsL -o /tmp/consul.zip \
     "https://releases.hashicorp.com/consul/${CONSULVERSION}/consul_${CONSULVERSION}_linux_amd64.zip"
sudo unzip -q /tmp/consul.zip -d /usr/local/bin
sudo chmod 0755 /usr/local/bin/consul
sudo chown root:root /usr/local/bin/consul

echo "Configure Consul"
mkdir_for_root /etc/consul.d
mkdir_for_root /opt/consul
sudo mv /tmp/linux/consul.service /etc/systemd/system/consul.service

echo "Configure Nomad"
mkdir_for_root /etc/nomad.d
mkdir_for_root /opt/nomad
mkdir_for_root $NOMAD_PLUGIN_DIR
sudo mv /tmp/linux/nomad.service /etc/systemd/system/nomad.service

echo "Install Nomad"
sudo mv /tmp/linux/provision.sh /opt/provision.sh
sudo chmod +x /opt/provision.sh
#/opt/provision.sh --nomad_version $NOMADVERSION --nostart
/opt/provision.sh --nomad_url http://nomad-release-staging.s3-website.us-west-2.amazonaws.com/nomad/1.0.0-beta3.3/nomad_1.0.0-beta3.3_linux_amd64.zip --nostart

echo "Installing third-party apt repositories"

# Docker
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"

sudo apt-get update

echo "Installing Docker"
sudo apt-get install -y docker-ce
sudo docker pull alpine:3.12

echo "Installing CNI plugins"
sudo mkdir -p /opt/cni/bin
wget -q -O - \
     https://github.com/containernetworking/plugins/releases/download/v0.8.6/cni-plugins-linux-amd64-v0.8.6.tgz \
    | sudo tar -C /opt/cni/bin -xz

echo "Configuring dnsmasq"

# disable systemd-resolved and configure dnsmasq to forward local requests to
# consul. the resolver files need to dynamic configuration based on the VPC
# address and docker bridge IP, so those will be rewritten at boot time.
sudo systemctl disable systemd-resolved.service
sudo mv /tmp/linux/dnsmasq /etc/dnsmasq.d/default
sudo chown root:root /etc/dnsmasq.d/default

# this is going to be overwritten at provisioning time, but we need something
# here or we can't fetch binaries to do the provisioning
echo 'nameserver 8.8.8.8' > /tmp/resolv.conf
sudo mv /tmp/resolv.conf /etc/resolv.conf

sudo systemctl restart dnsmasq

echo "Updating boot parameters"

# enable cgroup_memory and swap
sudo sed -i 's/GRUB_CMDLINE_LINUX="[^"]*/& cgroup_enable=memory swapaccount=1/' /etc/default/grub
sudo update-grub
