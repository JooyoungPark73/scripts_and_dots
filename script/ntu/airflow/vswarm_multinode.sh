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

common_init() {
    internal_init() {
        server_exec $1 "git clone --depth=1 https://github.com/vhive-serverless/vhive.git"
        server_exec $1 "mkdir -p /tmp/vhive-logs"
        server_exec $1 "export DEBIAN_FRONTEND="noninteractive" && ./vhive/scripts/cloudlab/setup_node.sh stock-only > >(tee -a /tmp/vhive-logs/setup_node.stdout) 2> >(tee -a /tmp/vhive-logs/setup_node.stderr >&2)"
        server_exec $1 'sudo screen -dmS containerd bash -c "containerd > >(tee -a /tmp/vhive-logs/containerd.stdout) 2> >(tee -a /tmp/vhive-logs/containerd.stderr >&2)"'
    }

    for node in "$@"
    do
        internal_init "$node" &
    done

    wait
}

function setup_master() {
    echo -e "${BLUE}Setting up master node: $MASTER_NODE${NC}"

    server_exec "$MASTER_NODE" 'tmux new -s master -d'

    server_exec "$MASTER_NODE" 'tmux send -t master "cd vhive && ./scripts/cluster/create_multinode_cluster.sh stock-only > >(tee -a /tmp/vhive-logs/create_multinode_cluster.stdout) 2> >(tee -a /tmp/vhive-logs/create_multinode_cluster.stderr >&2)" ENTER'

    # Get the join token from k8s.
    while [ ! "$LOGIN_TOKEN" ]
    do
        sleep 1
        server_exec "$MASTER_NODE" 'tmux capture-pane -t master -b token'
        LOGIN_TOKEN="$(server_exec "$MASTER_NODE" 'tmux show-buffer -b token | grep -B 3 "All nodes need to be joined"')"
        echo -e "${RED}$LOGIN_TOKEN${NC}"
    done
    # cut of last line
    LOGIN_TOKEN=${LOGIN_TOKEN%[$'\t\r\n']*}
    # remove the \
    LOGIN_TOKEN=${LOGIN_TOKEN/\\/}
    # remove all remaining tabs, line ends and returns
    LOGIN_TOKEN=${LOGIN_TOKEN//[$'\t\r\n']}
}

function setup_workers() {
    internal_setup() {
        node=$1

        echo -e "${BLUE}Setting up worker node: $node${NC}"
        server_exec $node "./vhive/scripts/cluster/setup_worker_kubelet.sh stock-only > >(tee -a /tmp/vhive-logs/setup_worker_kubelet.stdout) 2> >(tee -a /tmp/vhive-logs/setup_worker_kubelet.stderr >&2)"

        server_exec $node "sudo ${LOGIN_TOKEN} > >(tee -a /tmp/vhive-logs/kubeadm_join.stdout) 2> >(tee -a /tmp/vhive-logs/kubeadm_join.stderr >&2)"
        echo -e "${BLUE}Worker node $node has joined the cluster.${NC}"
    }

    for node in "$@"
    do
        internal_setup "$node" &
    done

    wait
}

function setup_master_vswarm() {
    
    echo -e "${BLUE}Setting up vswarm on master node: $MASTER_NODE${NC}"
    server_exec "$MASTER_NODE" "git clone https://github.com/vhive-serverless/vSwarm.git"
    server_exec "$MASTER_NODE" "sudo apt-get update"
    server_exec "$MASTER_NODE" "sudo apt-get install ca-certificates curl gnupg lsb-release"
    server_exec "$MASTER_NODE" "sudo mkdir -m 0755 -p /etc/apt/keyrings"
    server_exec "$MASTER_NODE" "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
    server_exec "$MASTER_NODE" "echo 'deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable' | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"
    server_exec "$MASTER_NODE" "sudo apt-get update"
    server_exec "$MASTER_NODE" "sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    server_exec "$MASTER_NODE" "sudo chmod 666 /var/run/docker.sock"
    server_exec "$MASTER_NODE" "sudo apt-get install -y htop"
    server_exec "$MASTER_NODE" "curl -sS https://webi.sh/k9s | sh"
    server_exec "$MASTER_NODE" "source ~/.config/envman/PATH.env"
}

###############################################
######## MAIN SETUP PROCEDURE IS BELOW ########
###############################################

{
    # Set up all nodes including the master
    common_init "$@"

    shift # make argument list only contain worker nodes (drops master node)

    setup_master
    setup_workers "$@"

    # Notify the master that all nodes have joined the cluster
    server_exec $MASTER_NODE 'tmux send -t master "y" ENTER'
    echo -e "${BLUE}Cluster setup finalised.${NC}"

    # Setup airflow on master node and worker nodes
    setup_master_vswarm
    echo -e "${BLUE}Master node $MASTER_NODE finalised.${NC}"
}