if [[ -n "$ZSH_VERSION" ]]; then
    SCRIPT_PATH=$(cd $(dirname $0) && pwd)
elif [[ -n "$BASH_VERSION" ]]; then
    SCRIPT_PATH=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
else
    SCRIPT_PATH=$(cd ~/.workon && pwd)
fi
VIRT_PATH="$SCRIPT_PATH/virtualenv"
MED_KF=~/.ssh/med-key

add_ssh_config() {
    local host=$1

    # Do nothing if config exists
    [[ $(grep "Host ${host##*@}" ~/.ssh/config) != "" ]] && return 0
    echo "Adding $host to ~/.ssh/config"
    # If parameter is not set, detect if it requres a tunnel then add the host to config
    cat >> ~/.ssh/config << EOF
Host ${host##*@}
  User ${host%%@*}
  IdentityFile ${MED_KF}
EOF
    return 0
}

deploy_key_to() {
    local host=$1
    local res=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10 $host echo 'ok' 2>&1)
    # Do nothing if the connection success
    [[ "$res" == "ok" ]] && return 0
    # Exit if the connection time out
    [[ "$res" == *"Connection timed out"* ]] && echo "Cannot reach $host" && return 1

    echo -e "Deploying public key to $host...\n"
    # Generate key if not exists
    [[ ! -f $MED_KF ]] && ssh-keygen -t rsa -N "" -f $MED_KF
    if [[ $SELF_TEST != "" ]]; then
        cat ${MED_KF}.pub >> /root/.ssh/authorized_keys
        return 0
    fi
    # Copy keys to remote (ESXi places in a different place)
    echo "Checking OS distribution, please login with password"
    res=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 $host uname -a 2>&1)
    if [[ "$res" == *"ESXi"* ]]; then
        echo "Copying key to remote, please enter password"
        cat ${MED_KF}.pub | ssh $host "cat - >> /etc/ssh/keys-root/authorized_keys"
    else
        ssh-copy-id -f -i ${MED_KF}.pub $host
    fi
    return 0
}

function check_connection() {
    echo -e "Checking connection..."
    local res=$(ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10 $1 echo 'ok' 2>&1)
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
    cp $VIRT_PATH/.bin/* $VIRT_PATH/$host/bin

    # Active virtual env and install dependencies in the virtual env
    source $VIRT_PATH/$host/bin/activate
    pip3 install -r $VIRT_PATH/.requirements.txt
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
    else
        # Exit if the host is not reachable
        ! check_connection "$host" && echo "Cannot connect to $host" && return 1
        source $VIRT_PATH/$host/bin/activate
    fi
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

