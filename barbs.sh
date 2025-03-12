#!/bin/bash
#
# Beach Automation Routine for Building Systems (BARBS)
# by Timothy Beach
# +-+-+-+-+-+-+-+-+-+-+-+-+-+-+
# |A|e|g|i|x|L|i|n|u|x|.|o|r|g|
# +-+-+-+-+-+-+-+-+-+-+-+-+-+-+
# License: GNU GPLv3
# VERSION: 20240312.1 (Updated from 20231126.1)

# Exit on error
set -e

#==============================================================================
# CONFIGURATION
#==============================================================================

# Repository URLs and paths
DOT_FILES_REPO="https://github.com/aegixlinux/gohan.git"
REPO_BRANCH="master"
AUR_HELPER="yay"

# Set temporary directory for downloaded files
TMP_DIR="/tmp"
PROGRAMS_CSV="${TMP_DIR}/aegix-programs.csv"

# Set terminal for child processes
export TERM=ansi

# Output log file
LOG_FILE="output.log"

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

# Display error message and exit
error() {
    printf "%s\n" "$1" >&2
    exit 1
}

# Log a message to the console
log_message() {
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] $1"
}

#==============================================================================
# PACKAGE MANAGEMENT FUNCTIONS
#==============================================================================

# Install a package using pacman
pacman_install() {
    pacman --noconfirm --needed -S "$1" >> "${LOG_FILE}" 2>&1
}

# Refresh package keys based on init system
refresh_keys() {
    case "$(readlink -f /sbin/init)" in
        *systemd*)
            whiptail --infobox "Refreshing Arch Keyring..." 7 40
            pacman --noconfirm -S archlinux-keyring >> "${LOG_FILE}" 2>&1
            ;;
        *)
            whiptail --infobox "Enabling Arch Repositories..." 7 40
            
            # Remove [community] section if it exists
            if grep -q "^\[community\]" /etc/pacman.conf; then
                whiptail --infobox "Removing [community] section from pacman.conf..." 7 60
                # Delete the [community] section and the Include line that follows it
                sed -i '/^\[community\]/,/^Include = \/etc\/pacman.d\/mirrorlist-arch$/d' /etc/pacman.conf
                log_message "Removed [community] section from pacman.conf"
            fi
            
            if ! grep -q "^\[universe\]" /etc/pacman.conf; then
                cat << EOF >> /etc/pacman.conf
[universe]
Server = https://universe.artixlinux.org/\$arch
Server = https://mirror1.artixlinux.org/universe/\$arch
Server = https://mirror.pascalpuffke.de/artix-universe/\$arch
Server = https://mirrors.qontinuum.space/artixlinux-universe/\$arch
Server = https://mirror1.cl.netactuate.com/artix/universe/\$arch
Server = https://ftp.crifo.org/artix-universe/\$arch
Server = https://artix.sakamoto.pl/universe/\$arch
EOF
                pacman -Sy --noconfirm >> "${LOG_FILE}" 2>&1
            fi
            
            pacman --noconfirm --needed -S artix-keyring artix-archlinux-support >> "${LOG_FILE}" 2>&1
            
            # Only add extra repository, skip community
            for repo in extra; do
                grep -q "^\[$repo\]" /etc/pacman.conf || 
                    echo "[$repo]
Include = /etc/pacman.d/mirrorlist-arch" >> /etc/pacman.conf
            done
            
            pacman -Sy >> "${LOG_FILE}" 2>&1
            pacman-key --populate archlinux >> "${LOG_FILE}" 2>&1
            ;;
    esac
}

# Manually install AUR helper
manual_install() {
    pacman -Qq "$1" && return 0
    
    whiptail --infobox "Installing \"$1\", an AUR helper..." 7 50
    sudo -u "${user_name}" mkdir -p "${src_repo_dir}/$1"
    
    sudo -u "${user_name}" git -C "${src_repo_dir}" clone --depth 1 --single-branch \
        --no-tags -q "https://aur.archlinux.org/$1.git" "${src_repo_dir}/$1" ||
        {
            cd "${src_repo_dir}/$1" || return 1
            sudo -u "${user_name}" git pull --force origin master
        }
    
    cd "${src_repo_dir}/$1" || exit 1
    sudo -u "${user_name}" makepkg --noconfirm -si >> "${LOG_FILE}" 2>&1 || return 1
}

# Install from official repositories
official_repo_install() {
    whiptail --title "BARBS Installation" --infobox "Installing \`$1\` ($n of $user_program_count). $1 $2" 9 70
    pacman_install "$1"
}

# Install from a git repository with make
git_make_install() {
    program_name="${1##*/}"
    program_name="${program_name%.git}"
    dir="${src_repo_dir}/${program_name}"
    
    whiptail --title "BARBS Installation" \
        --infobox "Installing \`$program_name\` ($n of $user_program_count) via \`git\` and \`make\`. $(basename "$1") $2" 8 70
    
    sudo -u "${user_name}" git -C "${src_repo_dir}" clone --depth 1 --single-branch \
        --no-tags -q "$1" "${dir}" ||
        {
            cd "${dir}" || return 1
            sudo -u "${user_name}" git pull --force origin master
        }
    
    cd "${dir}" || exit 1
    make >> "${LOG_FILE}" 2>&1
    make install >> "${LOG_FILE}" 2>&1
    cd /tmp || return 1
}

# Install from AUR
aur_repo_install() {
    whiptail --title "BARBS Installation" \
        --infobox "Installing \`$1\` ($n of $user_program_count) from the AUR. $1 $2" 9 70
    
    echo "${aur_installed_packages}" | grep -q "^$1$" && return 0
    sudo -u "${user_name}" ${AUR_HELPER} -S --noconfirm "$1" >> "${LOG_FILE}" 2>&1
}

# Install Python packages with pip
pip_install() {
    whiptail --title "BARBS Installation" \
        --infobox "Installing the Python package \`$1\` ($n of $user_program_count). $1 $2" 9 70
    
    [ -x "$(command -v "pip")" ] || pacman_install python-pip >> "${LOG_FILE}" 2>&1
    yes | pip install "$1"
}

# Process the program list and install programs
installation_loop() {
    # Copy or download the program list
    if [ -f "${user_programs_to_install}" ]; then
        cp "${user_programs_to_install}" "${PROGRAMS_CSV}"
    else
        curl -Ls "${user_programs_to_install}" | sed '/^#/d' > "${PROGRAMS_CSV}"
    fi
    
    user_program_count=$(wc -l < "${PROGRAMS_CSV}")
    aur_installed_packages=$(pacman -Qqm)
    
    n=0
    while IFS=, read -r tag program comment; do
        n=$((n + 1))
        
        # Clean up comment formatting if needed
        if echo "$comment" | grep -q "^\".*\"$"; then
            comment="$(echo "$comment" | sed -E "s/(^\"|\"$)//g")"
        fi
        
        case "$tag" in
            "A") aur_repo_install "$program" "$comment" ;;
            "G") git_make_install "$program" "$comment" ;;
            "P") pip_install "$program" "$comment" ;;
            *) official_repo_install "$program" "$comment" ;;
        esac
    done < "${PROGRAMS_CSV}"
}

#==============================================================================
# CONFIGURATION FUNCTIONS
#==============================================================================

# Install configuration files from git repository
gohan_install() {
    whiptail --infobox "Downloading and installing config files..." 7 60
    
    # Determine which branch to use
    [ -z "$3" ] && branch="master" || branch="${REPO_BRANCH}"
    
    # Create temporary directory
    dir=$(mktemp -d)
    
    # Create destination directory if it doesn't exist
    [ ! -d "$2" ] && mkdir -p "$2"
    
    # Set ownership
    chown "${user_name}:wheel" "$dir" "$2"
    
    # Clone repository
    sudo -u "${user_name}" git -C "${src_repo_dir}" clone --depth 1 \
        --single-branch --no-tags -q --recursive -b "$branch" \
        --recurse-submodules "$1" "$dir"
    
    # Copy files to destination
    sudo -u "${user_name}" cp -rfT "$dir" "$2"
}

# Install NeoVim plugins
vim_plugin_install() {
    whiptail --infobox "Installing neovim plugins..." 7 60
    
    mkdir -p "/home/${user_name}/.config/nvim/autoload"
    curl -Ls "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" > "/home/${user_name}/.config/nvim/autoload/plug.vim"
    chown -R "${user_name}:wheel" "/home/${user_name}/.config/nvim"
    sudo -u "${user_name}" nvim -c "PlugInstall|q|q"
}

#==============================================================================
# USER MANAGEMENT FUNCTIONS
#==============================================================================

# Prompt for new username and password
get_user_and_pw() {
    user_name=$(whiptail --inputbox "Enter a username for logging into your Aegix graphical environment." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
    
    while ! echo "$user_name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
        user_name=$(whiptail --nocancel --inputbox "The username you entered is not valid. Provide a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
    done
    
    pass1=$(whiptail --nocancel --passwordbox "Enter a passphrase for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
    pass2=$(whiptail --nocancel --passwordbox "Retype your passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)
    
    while ! [ "$pass1" = "$pass2" ]; do
        unset pass2
        pass1=$(whiptail --nocancel --passwordbox "Passphrases do not match.\\n\\nTry again." 10 60 3>&1 1>&2 2>&3 3>&1)
        pass2=$(whiptail --nocancel --passwordbox "Retype your passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)
    done
}

# Check if user already exists
user_check() {
    ! { id -u "$user_name" >> "${LOG_FILE}" 2>&1; } ||
        whiptail --title "WARNING" --yes-button "CONTINUE" \
            --no-button "No wait..." \
            --yesno "The user \`$user_name\` already exists on this system. Proceeding will OVERWRITE any conflicting user configuration for this user.\\n\\nUser $user_name's password will also be updated to what you just entered." 14 70
}

# Add user and set password
add_user_and_pw() {
    whiptail --infobox "Adding user \"$user_name\"..." 7 50
    
    useradd -m -g wheel -s /bin/zsh "$user_name" >> "${LOG_FILE}" 2>&1 ||
        usermod -a -G wheel "$user_name" && mkdir -p /home/"$user_name" && chown "$user_name":wheel /home/"$user_name"
    
    export src_repo_dir="/home/$user_name/.local/src"
    mkdir -p "$src_repo_dir"
    chown -R "$user_name":wheel "$(dirname "$src_repo_dir")"
    
    echo "$user_name:$pass1" | chpasswd
    unset pass1 pass2
}

#==============================================================================
# DIALOG FUNCTIONS
#==============================================================================

# Display welcome message
welcome_message() {
    whiptail --title "aegixlinux.org" \
        --msgbox "                    Welcome to BARBS!\\n\\n                    B - Beach \\n                    A - Automation \\n                    R - Routine for \\n                    B - Building \\n                    S - Systems.\\n\\nIf you made it here from the Aegix install.sh script, your base system is installed. We're now inside a chroot, and you're ready to commence with BARBS to set up a graphical environment.\\n\\nBARBS can also be run standalone, in some cases, on top of other distros." 21 60
}

# Display pre-installation message
pre_install_message() {
    whiptail --title "Ready?" --yes-button "Let's go!" \
        --no-button "No. Cancel BARBS!" \
        --yesno "Time to get up and stretch a bit.\\n\\nBARBS is about to run its lengthy installation routines.\\n\\nWe'll keep you notified how it's going along the way." 13 60 || {
        clear
        exit 1
    }
}

# Display completion message
finale() {
    whiptail --title "All done!" \
        --msgbox "Congrats! You're done with BARBS.\\n\\nIf you got here the traditional route from install.sh, you'll be returned to your nice, new system.\\n\\nIf you ran BARBS standalone, you can run startx as your new user. Logging in after reboot will land you in tty1 which will auto-run startx\\n\\nEnjoy\\nAegix" 16 90
}

#==============================================================================
# SYSTEM CONFIGURATION FUNCTIONS
#==============================================================================

# Configure pacman and makepkg settings
configure_pacman() {
    grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
    sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf
    sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf
}

# Setup user directories and files
setup_user_directories() {
    mkdir -p /home/$user_name/Downloads 
    mkdir -p /home/$user_name/Documents 
    mkdir -p /home/$user_name/Pictures 
    mkdir -p /home/$user_name/Music 
    mkdir -p /home/$user_name/Videos/obs 
    mkdir -p /home/$user_name/code 
    mkdir -p /home/$user_name/ss 
    mkdir -p /home/$user_name/Applications/vs-code-insider
    
    # Link background image if available
    if [ -f /root/aegix-bg.png ]; then
        ln -sf /root/aegix-bg.png /home/$user_name/.local/share/bg 
    else
        log_message "User-selected background does not exist."
    fi
    
    chown -R $user_name:wheel /home/$user_name/*
    chown -R $user_name:wheel /root
}

# Configure touchpad for tap to click
configure_touchpad() {
    [ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && cat > /etc/X11/xorg.conf.d/40-libinput.conf << EOF
Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
        # Enable left mouse button by tapping
        Option "Tapping" "on"
EndSection
EOF
}

# Disable terminal beep
disable_terminal_beep() {
    if lsmod | grep "pcspkr" &> /dev/null; then
        log_message "pcspkr module is loaded, removing..."
        rmmod pcspkr
        echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
    else
        log_message "pcspkr module is not loaded, moving on..."
    fi
}

# Configure DBUS for Artix Runit
configure_dbus() {
    mkdir -p /var/lib/dbus/
    dbus-uuidgen > /var/lib/dbus/machine-id
    echo "export \$(dbus-launch)" > /etc/profile.d/dbus.sh
}

# Setup sudo configuration
configure_sudo() {
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/barbs-temp
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    echo "Defaults editor=/usr/bin/nvim" > /etc/sudoers.d/02-barbs-visudo-editor
}

#==============================================================================
# MAIN EXECUTION
#==============================================================================

main() {
    # Initialize log file
    > "${LOG_FILE}"
    
    # Download program list if needed
    if [ ! -f "/root/aegix-programs.csv" ]; then
        log_message "Downloading program list..."
        curl -L aegixlinux.org/aegix-programs.csv -o /root/aegix-programs.csv
    fi
    user_programs_to_install="/root/aegix-programs.csv"
    
    # Welcome and get user confirmation
    welcome_message || error "User exited."
    get_user_and_pw || error "User exited."
    user_check || error "User exited."
    pre_install_message || error "User exited."
    
    # System preparation
    refresh_keys || error "Error refreshing keyring. Consider doing so manually."
    
    # Install required base packages
    log_message "Installing required base packages..."
    for pkg in curl ca-certificates base-devel git zsh; do
        whiptail --title "Installing Required Packages" \
            --infobox "Installing \`$pkg\` which is required to install and configure other programs." 8 70
        pacman_install "$pkg"
    done
    
    # User setup
    add_user_and_pw || error "Error adding username and/or password."
    
    # System configuration
    configure_sudo
    configure_pacman
    
    # Install AUR helper
    manual_install ${AUR_HELPER} || error "Failed to install AUR helper."
    
    # Install user programs
    installation_loop
    
    # Install configuration files
    gohan_install "${DOT_FILES_REPO}" "/home/${user_name}" "${REPO_BRANCH}"
    rm -rf "/home/${user_name}/.git/" "/home/${user_name}/README.md" "/home/${user_name}/LICENSE" "/home/${user_name}/FUNDING.yml"
    
    # Install NeoVim plugins if needed
    [ ! -f "/home/${user_name}/.config/nvim/autoload/plug.vim" ] && vim_plugin_install
    
    # Additional system configuration
    disable_terminal_beep
    chsh -s /bin/zsh "${user_name}" >> "${LOG_FILE}" 2>&1
    
    # Create necessary user directories
    sudo -u "${user_name}" mkdir -p "/home/${user_name}/.cache/zsh/"
    sudo -u "${user_name}" mkdir -p "/home/${user_name}/.config/abook/"
    sudo -u "${user_name}" mkdir -p "/home/${user_name}/.config/mpd/playlists/"
    
    # Configure DBUS
    configure_dbus
    
    # Configure touchpad
    configure_touchpad
    
    # Setup user directories and files
    setup_user_directories
    
    # Display completion message
    finale
}

# Execute main function
main