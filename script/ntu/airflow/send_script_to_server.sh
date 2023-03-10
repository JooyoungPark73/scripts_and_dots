#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

server_exec() {
    echo -e "${BLUE}$1: ${GREEN}$2${NC}"
    ssh -oStrictHostKeyChecking=no -p 22 "$1" "$2";
}

if [ $# == 2 ]
then
    echo -e "${BLUE}Copy script $1 to $2${NC}"
else 
    echo -e "${RED}Error: invalid number of input arguments. must have two.${NC}"
    exit 1
fi

scp ./$1 $2:~/
server_exec $2 "chmod +x ./$1"
server_exec $2 "./$1"