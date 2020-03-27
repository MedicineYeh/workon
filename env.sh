if [[ -n "$ZSH_VERSION" ]]; then
    SCRIPT_PATH=$(cd $(dirname $0) && pwd)
elif [[ -n "$BASH_VERSION" ]]; then
    SCRIPT_PATH=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
else
    SCRIPT_PATH=$(cd ~/.workon && pwd)
fi
VIRT_PATH="$SCRIPT_PATH/virtualenv"
SSH_KEY_WORKON=~/.ssh/med-key

add_ssh_config() {
    local host=$1

    # Create if file not exist
    [[ ! -f  ~/.ssh/config ]] && touch  ~/.ssh/config
    # Do nothing if config exists
    [[ $(grep "Host ${host##*@}" ~/.ssh/config) != "" ]] && return 0
    echo "Adding $host to ~/.ssh/config"
    # If parameter is not set, detect if it requres a tunnel then add the host to config
    cat >> ~/.ssh/config << EOF
Host ${host##*@}
  User ${host%%@*}
  IdentityFile ${SSH_KEY_WORKON}
EOF

    # Generate key if not exists
    [[ ! -f $SSH_KEY_WORKON ]] && ssh-keygen -t rsa -N "" -f $SSH_KEY_WORKON
    return 0
}

deploy_key_to() {
    local host=$1
    local res=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 $host echo 'ok' 2>&1)
    # Do nothing if the connection success
    [[ "$res" == "ok" ]] && return 0
    # Exit if the connection time out
    [[ "$res" == *"Connection timed out"* ]] && echo "Cannot reach $host" && return 1

    echo -e "Deploying public key to $host...\n"
    # Generate key if not exists
    [[ ! -f $SSH_KEY_WORKON ]] && ssh-keygen -t rsa -N "" -f $SSH_KEY_WORKON
    if [[ $SELF_TEST != "" ]]; then
        cat ${SSH_KEY_WORKON}.pub >> /root/.ssh/authorized_keys
        return 0
    fi
    # Copy keys to remote (ESXi places in a different place)
    echo "Checking OS distribution, please login with password"
    res=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 $host uname -a 2>&1)
    if [[ "$res" == *"ESXi"* ]]; then
        echo "Copying key to remote, please enter password"
        cat ${SSH_KEY_WORKON}.pub | ssh $host "cat - >> /etc/ssh/keys-root/authorized_keys"
    else
        ssh-copy-id -f -i ${SSH_KEY_WORKON}.pub $host
    fi
    return 0
}

function check_connection() {
    echo -e "Checking connection..."
    local res=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 $1 echo 'ok' 2>&1)
    [[ "$res" != "ok" ]] && return 1
    return 0
}

function create_env() {
    local host="$1"

    echo -e "Creating new virtual env...\n\n"
    # Create virtual env if not exists
    mkdir -p $VIRT_PATH/$host
    python3 -m venv --symlinks --clear $VIRT_PATH/$host

    # Prepare virtual environment
    echo "export JUMP_SERVER=$user@$host" >> $VIRT_PATH/$host/bin/activate
    [[ -d $VIRT_PATH/.bin ]] && cp $VIRT_PATH/.bin/* $VIRT_PATH/$host/bin

    # Active virtual env and install dependencies in the virtual env
    source $VIRT_PATH/$host/bin/activate
    [[ -f $VIRT_PATH/.requirements.txt ]] && pip3 install -r $VIRT_PATH/.requirements.txt
}

function __generate_proxy_port_file() {
    for port in {4000..5000}; do
        if [[ "$(lsof -i -P -n | grep $port)" == "" ]]; then
            echo $port > $VIRT_PATH/$host/PROXY_PORT
            break
        fi
    done
}

function __open_workon_proxy() {
    if [[ -f $VIRT_PATH/$host/PROXY_PORT ]]; then
        D_PORT=$(cat $VIRT_PATH/$host/PROXY_PORT)
        if [[ $(ps -aux | grep "ssh -D $D_PORT" | grep "$host" | wc -l) != 1 ]]; then
            # Found last record of port number but could not find existing process
            # Find another port numer and store it
            __generate_proxy_port_file
        fi
    else
        __generate_proxy_port_file
    fi
    # Load latest proxy port file
    D_PORT=$(cat $VIRT_PATH/$host/PROXY_PORT)
    # Create a new ssh daemon for SOCKS proxy if not exist
    [[ $(ps -aux | grep "ssh -D $D_PORT" | grep "$host" | wc -l) != 1 ]] && \
        /usr/bin/ssh -D $D_PORT -f -C -q -N "$host"
    export WORKON_PROXY="socks5://127.0.0.1:$D_PORT"
    echo "WORKON_PROXY=$WORKON_PROXY"
}

function workon() {
    [[ "$1" == "" ]] && echo "Please specify host_ip/FQDN" && exit 1
    local host="${1##*@}"
    local user="${1%%@*}"

    if [[ ! -d $VIRT_PATH/$host ]]; then
        if [[ "$user" == "$host" ]]; then
            echo 'This is the first time to connect. Please give username. EX: myname@127.0.0.1'
            return 1
        fi
        # Add ssh config
        add_ssh_config "${user}@${host}"

        ! deploy_key_to "${user}@${host}" && return 1

        # Exit if the host is reachable with identity file
        ! check_connection $host && echo "Cannot connect to $host with identity file" && return 1

        create_env $host

        __generate_proxy_port_file
    else
        # Exit if the host is not reachable
        ! check_connection "$host" && echo "Cannot connect to $host" && return 1
        source $VIRT_PATH/$host/bin/activate
    fi

    __open_workon_proxy

    return 0
}

# Shell completion support
if [[ -n "$ZSH_VERSION" ]]; then
    # assume Zsh
    function _comp_workon() {
        local hosts=$(ls $VIRT_PATH)
        local curr_arg_num=$CURRENT
        [[ $curr_arg_num > 2 ]] && return 0
        _alternative "dirs:user directory:($hosts)"
    }
    compdef _comp_workon workon
elif [[ -n "$BASH_VERSION" ]]; then
    # assume Bash
    function _comp_workon() {
        local hosts=$(ls $VIRT_PATH)
        local cur=$2
        local curr_arg_num=$(( $COMP_CWORD + 1 ))
        [[ $curr_arg_num > 2 ]] && return 0
        COMPREPLY=()
        COMPREPLY=($( compgen -W "$hosts" -- $cur ) )
    }
    complete -F _comp_workon workon
fi

