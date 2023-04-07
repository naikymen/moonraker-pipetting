#!/bin/bash
# This script installs Moonraker on a Raspberry Pi machine running
# Arch Linux (requiring yay for installing python-gpiod from the AUR).

# Possible usage: https://moonraker.readthedocs.io/en/latest/installation/#installing-moonraker
# export PARENT_PATH=${HOME}/Projects/GOSH/gosh-col-dev
# export MOONRAKER_VENV=${PARENT_PATH}/moonraker/moonraker-env
# ./scripts/install-moonraker.sh -z -x -d ${PARENT_PATH}/moonraker/printer_data

# Possible startup command:
# source moonraker-env/bin/activate
# python moonraker/moonraker.py

# Force script to exit if an error occurs
set -e





# Step 1: define variables
# Find SRCDIR from the pathname of this script
SRCDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. && pwd )"
# Directory to where you cloned "pipetting-klipper-group.git"
KLIPPER_GROUP=`pwd`
# Misc variables
SYSTEMDDIR="/etc/systemd/system"
REBUILD_ENV="${MOONRAKER_REBUILD_ENV:-n}"              # "n" by default
FORCE_DEFAULTS="${MOONRAKER_FORCE_DEFAULTS:-n}"        # "n" by default
DISABLE_SYSTEMCTL="${MOONRAKER_DISABLE_SYSTEMCTL:-n}"  # "n" by default
SKIP_POLKIT="${MOONRAKER_SKIP_POLKIT:-n}"              # "n" by default
CONFIG_PATH="${MOONRAKER_CONFIG_PATH}"
LOG_PATH="${MOONRAKER_LOG_PATH}"
DATA_PATH="${MOONRAKER_DATA_PATH:-${KLIPPER_GROUP}/printer_data}"
INSTANCE_ALIAS="${MOONRAKER_ALIAS:-moonraker}"         # "moonraker" by default
SERVICE_VERSION="1"
MACHINE_PROVIDER="systemd_cli"
# Modified PYTHONDIR to use KLIPPER_GROUP (pwd) instead of HOME by default.
PYTHONDIR="${MOONRAKER_VENV:-${KLIPPER_GROUP}/moonraker-env}"

# Parse command line arguments
while getopts "rfzxc:l:d:a:" arg; do
    case $arg in
        r) REBUILD_ENV="y";;
        f) FORCE_DEFAULTS="y";;
        z) DISABLE_SYSTEMCTL="y";;
        x) SKIP_POLKIT="y";;
        c) CONFIG_PATH=$OPTARG;;
        l) LOG_PATH=$OPTARG;;
        d) DATA_PATH=$OPTARG;;
        a) INSTANCE_ALIAS=$OPTARG;;
    esac
done

# Undocumented DATA_PATH logic
if [ -z "${DATA_PATH}" ]; then
    if [ "${INSTANCE_ALIAS}" = "moonraker" ]; then
        DATA_PATH="${DATA_PATH}/printer_data"
    else
        num="$( echo ${INSTANCE_ALIAS} | grep  -Po "moonraker[-_]?\K\d+" || true )"
        if [ -n "${num}" ]; then
            DATA_PATH="${HOME}/printer_${num}_data"
        else
            DATA_PATH="${HOME}/${INSTANCE_ALIAS}_data"
        fi
    fi
fi

# Undocumented SERVICE_FILE logic
SERVICE_FILE="${SYSTEMDDIR}/${INSTANCE_ALIAS}.service"

# Step 2: Clean up legacy installation
cleanup_legacy() {
    if [ -f "/etc/init.d/moonraker" ]; then
        # Stop Moonraker Service
        echo "#### Cleanup legacy install script"
        sudo systemctl stop moonraker
        sudo update-rc.d -f moonraker remove
        sudo rm -f /etc/init.d/moonraker
        sudo rm -f /etc/default/moonraker
    fi
}

# Step 3: Install packages
install_packages()
{
    PKGLIST="python-virtualenv openjpeg2"
    PKGLIST="${PKGLIST} curl openssl lmdb"
    PKGLIST="${PKGLIST} libsodium zlib packagekit"  # Is "libjpeg-dev" provided by openjpeg2 above?
    PKGLIST="${PKGLIST} wireless_tools"

    AURLIST="python-gpiod"  # https://aur.archlinux.org/packages/python-gpiod

    # Update system package info
    # Install desired packages
    report_status "Running pacman and yay install (-S)"
    sudo pacman -S ${PKGLIST} --needed
    yay -S ${AURLIST} --needed --answerclean None --answerdiff None --answeredit None
}

# Step 4: Create python virtual environment
create_virtualenv()
{
    report_status "Installing python virtual environment at ${PYTHONDIR}"

    # If venv exists and user prompts a rebuild, then do so
    if [ -d ${PYTHONDIR} ] && [ $REBUILD_ENV = "y" ]; then
        report_status "Removing old virtualenv"
        rm -rf ${PYTHONDIR}
    fi

    if [ ! -d ${PYTHONDIR} ]; then
        python3 -m venv ${PYTHONDIR}
        #GET_PIP="${HOME}/get-pip.py"
        #curl https://bootstrap.pypa.io/pip/3.6/get-pip.py -o ${GET_PIP}
        #${PYTHONDIR}/bin/python ${GET_PIP}
        #rm ${GET_PIP}
    fi

    # Install/update dependencies
    ${PYTHONDIR}/bin/pip install -r ${SRCDIR}/scripts/moonraker-requirements.txt
}

# Step 5: Initialize data folder
init_data_path()
{
    report_status "Initializing Moonraker Data Path at ${DATA_PATH}"
    config_dir="${DATA_PATH}/config"
    logs_dir="${DATA_PATH}/logs"
    env_dir="${DATA_PATH}/systemd"
    config_file="${DATA_PATH}/config/moonraker.conf"
    [ ! -e "${DATA_PATH}" ] && mkdir ${DATA_PATH}
    [ ! -e "${config_dir}" ] && mkdir ${config_dir}
    [ ! -e "${logs_dir}" ] && mkdir ${logs_dir}
    [ ! -e "${env_dir}" ] && mkdir ${env_dir}
    [ -n "${CONFIG_PATH}" ] && config_file=${CONFIG_PATH}
    # Write initial configuration for first time installs
    if [ ! -f $SERVICE_FILE ] && [ ! -e "${config_file}" ]; then
        report_status "Writing Config File ${config_file}:\n"
        /bin/sh -c "cat > ${config_file}" << EOF
# Moonraker Configuration File

[server]
host: 0.0.0.0
port: 7125
# Make sure the klippy_uds_address is correct.  It is initialized
# to the default address.
klippy_uds_address: /tmp/klippy_uds

[machine]
provider: ${MACHINE_PROVIDER}

EOF
        cat ${config_file}
    fi
}

# Step 6: Install startup script
install_script()
{
    # Create systemd service file
    ENV_FILE="${DATA_PATH}/systemd/moonraker.env"
    if [ ! -f $ENV_FILE ] || [ $FORCE_DEFAULTS = "y" ]; then
        rm -f $ENV_FILE
        args="MOONRAKER_ARGS=\"-m moonraker"
        [ -n "${CONFIG_PATH}" ] && args="${args} -c ${CONFIG_PATH}"
        [ -n "${LOG_PATH}" ] && args="${args} -l ${LOG_PATH}"
        args="${args} -d ${DATA_PATH}"
        args="${args}\""
        args="${args}\nPYTHONPATH=\"${SRCDIR}\""
        echo -e $args > $ENV_FILE
    fi
    [ -f $SERVICE_FILE ] && [ $FORCE_DEFAULTS = "n" ] && return
    report_status "Installing system start script..."
    sudo groupadd -f moonraker-admin
    sudo /bin/sh -c "cat > ${SERVICE_FILE}" << EOF
# systemd service file for moonraker
[Unit]
Description=API Server for Klipper SV${SERVICE_VERSION}
Requires=network-online.target
After=network-online.target

[Install]
WantedBy=multi-user.target

[Service]
Type=simple
User=$USER
SupplementaryGroups=moonraker-admin
RemainAfterExit=yes
EnvironmentFile=${ENV_FILE}
ExecStart=${PYTHONDIR}/bin/python \$MOONRAKER_ARGS
Restart=always
RestartSec=10
EOF
# Use systemctl to enable the klipper systemd service script
    if [ $DISABLE_SYSTEMCTL = "n" ]; then
        sudo systemctl enable "${INSTANCE_ALIAS}.service"
        sudo systemctl daemon-reload
    fi
}

# Step 7: Validate/Install polkit rules
check_polkit_rules()
{
    if [ ! -x "$(command -v pkaction)" ]; then
        return
    fi
    POLKIT_VERSION="$( pkaction --version | grep -Po "(\d+\.?\d*)" )"
    NEED_POLKIT_INSTALL="n"
    if [ "$POLKIT_VERSION" = "0.105" ]; then
        POLKIT_LEGACY_FILE="/etc/polkit-1/localauthority/50-local.d/10-moonraker.pkla"
        # legacy policykit rules don't give users other than root read access
        if sudo [ ! -f $POLKIT_LEGACY_FILE ]; then
            NEED_POLKIT_INSTALL="y"
        fi
    else
        POLKIT_FILE="/etc/polkit-1/rules.d/moonraker.rules"
        POLKIT_USR_FILE="/usr/share/polkit-1/rules.d/moonraker.rules"
        if [ ! -f $POLKIT_FILE ] && [ ! -f $POLKIT_USR_FILE ]; then
            NEED_POLKIT_INSTALL="y"
        fi
    fi
    if [ "${NEED_POLKIT_INSTALL}" = "y" ]; then
        if [ "${SKIP_POLKIT}" = "y" ]; then
            echo -e "\n*** No PolicyKit Rules detected, run 'set-policykit-rules.sh'"
            echo "*** if you wish to grant Moonraker authorization to manage"
            echo "*** system services, reboot/shutdown the system, and update"
            echo "*** packages."
        else
            report_status "Installing PolKit Rules"
            ${SRCDIR}/scripts/set-policykit-rules.sh -z
            MACHINE_PROVIDER="systemd_dbus"
        fi
    else
        MACHINE_PROVIDER="systemd_dbus"
    fi
}

# Step 8: Start server
start_software()
{
    report_status "Launching Moonraker API Server..."
    sudo systemctl restart ${INSTANCE_ALIAS}
}

# Helper functions
report_status()
{
    echo -e "\n\n###### $1"
}

verify_ready()
{
    if [ "$EUID" -eq 0 ]; then
        echo "This script must not run as root"
        exit -1
    fi
}

# Run installation steps defined above
verify_ready
#cleanup_legacy
install_packages
create_virtualenv
init_data_path
#install_script
#check_polkit_rules
#if [ $DISABLE_SYSTEMCTL = "n" ]; then
#    start_software
#fi
