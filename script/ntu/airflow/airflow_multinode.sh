#!/usr/bin/env bash

MASTER_NODE=$1


server_exec() {
    ssh -oStrictHostKeyChecking=no -p 22 "$1" "$2";
}

common_init() {
    internal_init() {
        server_exec $1 "git clone --depth=1 https://github.com/vhive-serverless/vhive.git"
        server_exec $1 "cd vhive; mkdir -p /tmp/vhive-logs"
        server_exec $1 "./scripts/cloudlab/setup_node.sh stock-only use-stargz > >(tee -a /tmp/vhive-logs/setup_node.stdout) 2> >(tee -a /tmp/vhive-logs/setup_node.stderr >&2)"
        server_exec $1 'tmux new -s containerd -d'
        server_exec $1 'tmux send -t containerd sudo screen -dmS containerd bash -c "containerd > >(tee -a /tmp/vhive-logs/containerd.stdout) 2> >(tee -a /tmp/vhive-logs/containerd.stderr >&2)" ENTER'
    }

    for node in "$@"
    do
        internal_init "$node" &
    done

    wait
}

function setup_master() {
    echo "Setting up master node: $MASTER_NODE"

    server_exec "$MASTER_NODE" 'tmux new -s master -d'

    MN_CLUSTER="./scripts/cluster/create_multinode_cluster.sh stock-only > >(tee -a /tmp/vhive-logs/create_multinode_cluster.stdout) 2> >(tee -a /tmp/vhive-logs/create_multinode_cluster.stderr >&2)"
    server_exec "$MASTER_NODE" "tmux send -t master \"$MN_CLUSTER\" ENTER"

    # Get the join token from k8s.
    while [ ! "$LOGIN_TOKEN" ]
    do
        sleep 1
        server_exec "$MASTER_NODE" 'tmux capture-pane -t master -b token'
        LOGIN_TOKEN="$(server_exec "$MASTER_NODE" 'tmux show-buffer -b token | grep -B 3 "All nodes need to be joined"')"
        echo "$LOGIN_TOKEN"
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

        echo "Setting up worker node: $node"
        server_exec $node "./scripts/cluster/setup_worker_kubelet.sh stock-only > >(tee -a /tmp/vhive-logs/setup_worker_kubelet.stdout) 2> >(tee -a /tmp/vhive-logs/setup_worker_kubelet.stderr >&2)"

        server_exec $node "sudo ${LOGIN_TOKEN} > >(tee -a /tmp/vhive-logs/kubeadm_join.stdout) 2> >(tee -a /tmp/vhive-logs/kubeadm_join.stderr >&2)"
        echo "Worker node $node has joined the cluster."
    }

    for node in "$@"
    do
        internal_setup "$node" &
    done

    wait
}

function setup_airflow() {
    master_setup(){
    echo "Setting up airflow"
    server_exec "$MASTER_NODE" "git clone git clone https://github.com/vhive-serverless/airflow.git"
    for node in "$@"
    do
        server_exec "$node" "sudo mkdir -p /mnt/data{0..19}"
        server_exec "$node" "sudo chmod 777 /mnt/data{0..19}"
    done
    server_exec "$MASTER_NODE" "cd airflow; ./scripts/setup_airflow.sh"
    server_exec "$MASTER_NODE" "sudo apt install -y docker.io"
    server_exec "$MASTER_NODE" "sudo chmod 666 /var/run/docker.sock"
    server_exec "$MASTER_NODE" "sudo apt-get install -y htop python3-pip"
    server_exec "$MASTER_NODE" "pip install pendulum"
    server_exec "$MASTER_NODE" "curl -sS https://webi.sh/k9s | sh"
    server_exec "$MASTER_NODE" "source ~/.config/envman/PATH.env"

    }
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
    echo "Master node $MASTER_NODE finalised."

    setup_airflow

}