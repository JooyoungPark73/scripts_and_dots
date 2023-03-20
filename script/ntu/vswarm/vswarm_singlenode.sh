#!/usr/bin/env bash

# By B Layer from https://unix.stackexchange.com/a/403894
for param; do 
    [[ ! $param == 'ssh' ]] && newparams+=("$param")
done
set -- "${newparams[@]}"  # filter out 'ssh' from arguments

MASTER_NODE=$1

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# referred to https://github.com/eth-easl/loader/blob/main/scripts/setup/create_multinode.sh

server_exec() {
    ssh -oStrictHostKeyChecking=no -p 22 "$1" "$2";
}

function setup_master() {
    echo -e "${BLUE}Setting up master node: $MASTER_NODE${NC}"
    server_exec "$MASTER_NODE" "git clone --depth=1 https://github.com/vhive-serverless/vhive.git"
    server_exec "$MASTER_NODE" "mkdir -p /tmp/vhive-logs"
    server_exec "$MASTER_NODE" "export DEBIAN_FRONTEND="noninteractive" && ./vhive/scripts/cloudlab/setup_node.sh stock-only"
    server_exec "$MASTER_NODE" 'sudo screen -dmS containerd containerd; sleep 5;'
    server_exec "$MASTER_NODE" 'source /etc/profile && go build;'
    server_exec "$MASTER_NODE" 'tmux new -s master -d'
    server_exec "$MASTER_NODE" 'tmux send -t master "cd vhive && ./scripts/cluster/create_one_node_cluster.sh stock-only" ENTER'
}

function setup_master_vswarm() {
    
    echo -e "${BLUE}Setting up vswarm on master node: $MASTER_NODE${NC}"
    server_exec "$MASTER_NODE" "git clone https://github.com/vhive-serverless/vSwarm.git"
    server_exec "$MASTER_NODE" "sudo apt-get update"
    server_exec "$MASTER_NODE" "sudo apt-get install -y ca-certificates curl gnupg lsb-release"
    server_exec "$MASTER_NODE" "sudo mkdir -m 0755 -p /etc/apt/keyrings"
    server_exec "$MASTER_NODE" "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
    server_exec "$MASTER_NODE" "echo 'deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable' | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"
    server_exec "$MASTER_NODE" "sudo apt-get update"
    server_exec "$MASTER_NODE" "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    server_exec "$MASTER_NODE" "sudo chmod 666 /var/run/docker.sock"
    server_exec "$MASTER_NODE" "sudo apt-get install -y htop"
    server_exec "$MASTER_NODE" "curl -sS https://webi.sh/k9s | sh"
    server_exec "$MASTER_NODE" "source ~/.config/envman/PATH.env"
}

###############################################
######## MAIN SETUP PROCEDURE IS BELOW ########
###############################################

{
    setup_master
    echo -e "${BLUE}Cluster setup finalised.${NC}"

    # Setup airflow on master node and worker nodes
    setup_master_vswarm
    echo -e "${BLUE}Master node $MASTER_NODE finalised.${NC}"
}