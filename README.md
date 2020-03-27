# Connect to private LAN like your LAN

Run the following command to install/upgrade the latest release.
``` bash
bash <(curl -s -L https://raw.githubusercontent.com/MedicineYeh/workon/master/easy_install.sh)
```

# Usage
* Run `workon USER@JUMP_SERVER_IP` to start the virtual env
* Run `deactivate` to exit virtual env


# Advantages
* It's designed for connecting to private LAN servers with predefined convenience.
* It's stateless. No connection built when using the virtual env.
* It's transparant. Use ssh/scp commands like you usually do.

