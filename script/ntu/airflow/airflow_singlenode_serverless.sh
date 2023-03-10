#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

{
    export DEBIAN_FRONTEND=noninteractive

    pushd ~
    echo -e "${BLUE}cloning vhive${NC}"
    git clone --depth=1 https://github.com/vhive-serverless/vhive.git
    mkdir -p /tmp/vhive-logs
    pushd vhive
    echo -e "${BLUE}setting up vhive environment${NC}"
    ./scripts/cloudlab/setup_node.sh stock-only

    sudo screen -d -m containerd
    ./scripts/cluster/create_one_node_cluster.sh stock-only

    popd
    echo -e "${BLUE}cloning airflow${NC}"
    git clone https://github.com/vhive-serverless/airflow.git
    pushd airflow
    echo -e "${BLUE}setting up airflow${NC}"
    ./scripts/setup_airflow.sh

    popd
    # Install Docker
    sudo apt install -y docker.io
    sudo chmod 666 /var/run/docker.sock

    # Some Additional Packages that I will use
    echo -e "${BLUE}setting up additional packages${NC}"
    sudo apt-get install -y htop python3-pip
    pip install pendulum
    curl -sS https://webi.sh/k9s | sh
    source ~/.config/envman/PATH.env
}