#!/bin/sh

##
# Metadata
##

# Beach Automation Routine for Building Systems (BARBS)
# by Timothy Beach
# +-+-+-+-+-+-+-+-+-+-+-+-+-+-+
# |A|e|g|i|x|L|i|n|u|x|.|o|r|g|
# +-+-+-+-+-+-+-+-+-+-+-+-+-+-+
# License: GNU GPLv3
# VERSION: 20231126.1

# Verbosity of comments are for pedagogical purposes.

##
# Script
##

# Enables the script to exit immediately if a command or pipeline has an error.
# This is the safest way to ensure that an unexpected error won't continue to execute further commands.
set -e

###
## Initial Setup
###

# Can be assigned to your own dotfiles repo if you were to fork gohan or create your own.
dot_files_repo="https://github.com/aegixlinux/gohan.git"

# Can be edited to point to your own csv file program list.
user_programs_to_install="https://github.com/aegixlinux/barbs/raw/master/aegix-programs.csv"

# Everyones favorite AUR helper.
aur_helper="yay"

# Assigns the branch of your dotfiles repo to use.
repo_branch="master"

# Set the terminal to the ANSI standard for child processes.
# This may break on GUI terminals.
export TERM=ansi

###
## Functions
###

####
### Installation Functions
####

# pacman_install function:
# Installs a given package using pacman.
# The --noconfirm flag automatically answers yes to all prompts.
# The --needed flag prevents reinstallation of up-to-date packages.
pacman_install() {
	# pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
	pacman --noconfirm --needed -S "$1" >> output.log 2>&1

}

# error function:
# Prints an error message to stderr and exits the script.
# The function prints the error message to stderr (>&2) and exits the script with a non-zero status to indicate an error.
# Note: The error message is output using printf to ensure it is formatted correctly.
error() {
	printf "%s\n" "$1" >&2
	exit 1
}

# refresh_keys function:
# Refreshes the Arch keyring or enables Arch repositories based on the init system.
# In case systemd is ever supported in the future.
# Runit only for now.
refresh_keys() {
	# This case statement checks the path that the /sbin/init symlink points to.
	# This is used to determine which init system the OS is using,
	# as this can affect how certain commands should be run.
	# The -f option to readlink canonicalizes the path, resolving all symlinks.
	case "$(readlink -f /sbin/init)" in
	# This line checks if the init system is systemd.
	# If it is, the code between this line and the following ;; is run.
	*systemd*)
		whiptail --infobox "Refreshing Arch Keyring..." 7 40
		pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1
		# pacman --noconfirm -S archlinux-keyring >> output.log 2>&1
		;;
	# If the init system is not systemd, the code between this line and the next ;; is run.
	*)
		whiptail --infobox "Enabling Arch Repositories..." 7 40
		# This if statement checks if the [universe] repository is already listed in the pacman configuration file.
		# If it is not, it adds a set of universe repositories to the configuration and synchronizes the package databases.
		if ! grep -q "^\[universe\]" /etc/pacman.conf; then
			echo "[universe]
Server = https://universe.artixlinux.org/\$arch
Server = https://mirror1.artixlinux.org/universe/\$arch
Server = https://mirror.pascalpuffke.de/artix-universe/\$arch
Server = https://mirrors.qontinuum.space/artixlinux-universe/\$arch
Server = https://mirror1.cl.netactuate.com/artix/universe/\$arch
Server = https://ftp.crifo.org/artix-universe/\$arch
Server = https://artix.sakamoto.pl/universe/\$arch" >>/etc/pacman.conf
			pacman -Sy --noconfirm >/dev/null 2>&1
			# pacman -Sy --noconfirm >> output.log 2>&1
		fi
		pacman --noconfirm --needed -S \
			artix-keyring artix-archlinux-support >/dev/null 2>&1
			# artix-keyring artix-archlinux-support >> output.log 2>&1
		# This for loop checks if the extra and community repositories are enabled.
		# If they are not, it adds the necessary repository information to the pacman configuration file.
		for repo in extra community; do
			grep -q "^\[$repo\]" /etc/pacman.conf ||
				echo "[$repo]
Include = /etc/pacman.d/mirrorlist-arch" >>/etc/pacman.conf
		done
		# This line synchronizes the package databases, effectively updating the list of available packages.
		pacman -Sy >/dev/null 2>&1
		# pacman -Sy >> output.log 2>&1
		# This line imports the Arch keyring, effectively updating the keys used to verify packages.
		pacman-key --populate archlinux >/dev/null 2>&1
		# pacman-key --populate archlinux >> output.log 2>&1
		;;
	# This line marks the end of the case statement.
	# esac is case spelled backwards.yay
	esac
}

# manual_install function:
# Manually installs a package, and currently it is only used for "yay" the AUR helper.
# Checks if the package is already installed using pacman. 
# If not, clones the package's repository from AUR and pulls any updates if the repository already exists. 
# Finally, builds and installs the package using makepkg.
# Note: This function is designed to be run after a repository directory (src_repo_dir) is created and the corresponding variable is set. 
# Also, it suppresses the output of makepkg.
manual_install() {
	# This checks if the package (whose name is provided as an argument $1 to the function) is already installed.
	# If it is, the function returns 0 (success) and ends.
	# If not, the function continues.
	pacman -Qq "$1" && return 0
	# This line uses the whiptail command to display an informational message to the user indicating that the package is being installed.
	# The numbers 7 50 specify the size of the message box.
	whiptail --infobox "Installing \"$1\", an AUR helper..." 7 50
	sudo -u "$user_name" mkdir -p "$src_repo_dir/$1"
	sudo -u "$user_name" git -C "$src_repo_dir" clone --depth 1 --single-branch \
		--no-tags -q "https://aur.archlinux.org/$1.git" "$src_repo_dir/$1" ||
		{
			cd "$src_repo_dir/$1" || return 1
			sudo -u "$user_name" git pull --force origin master
		}
	cd "$src_repo_dir/$1" || exit 1
	sudo -u "$user_name" \
		makepkg --noconfirm -si >/dev/null 2>&1 || return 1
		# makepkg --noconfirm -si >> output.log 2>&1 || return 1
}

# official_repo_install function:
# Installs a specified program from the main repository.
# Displays an informational dialog about the ongoing installation using whiptail. Then, calls the pacman_install function to install the program.
official_repo_install() {
	whiptail --title "BARBS Installation" --infobox "Installing \`$1\` ($n of $user_program_count). $1 $2" 9 70
	pacman_install "$1"
}

# git_make_install function:
# Clones a git repository and builds the project using make, then installs it.
# The function first extracts the program name from the repository URL.
# It then creates a directory for the program and clones the git repository into it.
# If the repository already exists, it pulls the latest changes.
# Afterwards, it changes to the program's directory, builds, and installs it using make.
git_make_install() {
	# These lines extract the name of the program to be installed.
	# The program's Git repository URL is expected to be the first argument ($1) to the function.
	# The first line removes the directory part of the URL, and the second line removes the .git suffix, leaving just the program name.
	program_name="${1##*/}"
	program_name="${program_name%.git}"
	# This line constructs the directory path where the program's repository will be cloned.
	dir="$src_repo_dir/$program_name"
	# The message includes the name of the program, the current progress ($n of $user_program_count), and a comment about the program ($2).
	whiptail --title "BARBS Installation" \
		--infobox "Installing \`$program_name\` ($n of $user_program_count) via \`git\` and \`make\`. $(basename "$1") $2" 8 70
	# This line clones the git repository of the program to be installed.
	# The sudo -u "$user_name" portion of the command runs the command as the user specified by the variable $user_name.
	# The -C "$src_repo_dir" option specifies the directory where the git clone command is run.
	# --depth 1 and --single-branch options limit the history of the cloned repository to the latest commit of the main branch, reducing the size and time taken to clone the repository.
	# --no-tags prevents the cloning of any tags,
	# and -q runs the command quietly, without producing output.
	# $1 is the URL of the git repository
	# and $dir is the target directory to clone the repository into.
	sudo -u "$user_name" git -C "$src_repo_dir" clone --depth 1 --single-branch \
		--no-tags -q "$1" "$dir" ||
		# The || operator is a logical OR.
		# If the preceding git clone command fails (perhaps because the repository has already been cloned before),
		# then the code inside the braces {} is executed.
		# This code first navigates into the directory of the program with cd "$dir"
		# and if it can't change directory, it returns 1 indicating a failure.
		# Then, it pulls the latest changes from the repository using git pull --force origin master, forcibly updating the local copy of the repository.
		{
			cd "$dir" || return 1
			sudo -u "$user_name" git pull --force origin master
		}
	# This line changes the current directory to the program's directory,
	# returning non-zero (failure) if it can't change directory.
	cd "$dir" || exit 1
	# This line builds the program using make.
	make >/dev/null 2>&1
	# make >> output.log 2>&1
	# This line installs the program using make install.
	make install >/dev/null 2>&1
	# make install >> output.log 2>&1
	# This line returns to the previous directory,
	# returning non-zero (failure) if it can't change directory.
	cd /tmp || return 1
}

# aur_repo_install function:
# Installs a given program from the Arch User Repository (AUR) using the specified AUR helper.
# It first checks if the program is already installed by searching for the program name in the $aur_installed_packages variable.
# If the program is not installed, it uses the AUR helper to install the program. 
# The --noconfirm flag automatically answers yes to all prompts.
# Output: None directly (affects system state by installing a program).
aur_repo_install() {
	whiptail --title "BARBS Installation" \
		--infobox "Installing \`$1\` ($n of $user_program_count) from the AUR. $1 $2" 9 70
	echo "$aur_installed_packages" | grep -q "^$1$" && return 0
	# sudo -u "$user_name" $aur_helper -S --noconfirm "$1" >/dev/null 2>&1
	sudo -u "$user_name" $aur_helper -S --noconfirm "$1" >> output.log 2>&1
}

# pip_install function:
# Installs a given Python package using pip.
# It first checks if pip is installed on the system, if not, it installs python-pip using pacman_install.
# Then, it uses pip to install the specified Python package.
pip_install() {
	whiptail --title "BARBS Installation" \
		--infobox "Installing the Python package \`$1\` ($n of $user_program_count). $1 $2" 9 70
	# This line checks if pip is installed on the system, if not, it installs python-pip using pacman_install.
	[ -x "$(command -v "pip")" ] || pacman_install python-pip >/dev/null 2>&1
	# [ -x "$(command -v "pip")" ] || pacman_install python-pip >> output.log 2>&1
	# This line uses the pip install command to install the Python package specified by $1.
	# The yes | part automatically answers "yes" to any prompts that might appear during the installation process,
	# thereby making the installation non-interactive.
	yes | pip install "$1"
}

# installation_loop function:
# Loops through a CSV file of programs to install and calls the corresponding installation function.
# The CSV file is expected to be in the format "tag,program name,comment".
# First, it checks if the file "$user_programs_to_install" exists locally, if it does, it's copied to /tmp/aegix-programs.csv.
# If the file does not exist locally, it's downloaded and processed to remove any commented out lines.
# Then, it loops through each line of the CSV file, with each line consisting of a tag, a program name, and a comment.
# Depending on the tag, it calls aur_repo_install, git_make_install, pip_install, or official_repo_install to install the program.
installation_loop() {
	# test -f checks if the file exists and is a regular file.
	# If the file exists, it's copied to /tmp/aegix-programs.csv.
	# If the file does not exist, it's downloaded and processed to remove any commented out lines.
	(test -f "$user_programs_to_install" && cp "$user_programs_to_install" /tmp/aegix-programs.csv) ||
		curl -Ls "$user_programs_to_install" | sed '/^#/d' >/tmp/aegix-programs.csv
	user_program_count=$(wc -l </tmp/aegix-programs.csv)
	# The $aur_installed_packages variable contains a list of all installed AUR packages.
	aur_installed_packages=$(pacman -Qqm)
	# IFS stands for Internal Field Separator. It's used to split the CSV file into fields, and it is only changed for the duration of the read command.
	# The read command reads a line from the CSV file and splits it into fields using the IFS variable.
	# The -r flag prevents backslashes from being interpreted as escape characters.
	while IFS=, read -r tag program comment; do
		n=$((n + 1))
		# The echo command prints out the value of the $comment variable.
		# This value is then piped (|) to the grep command.
		# The -q option for grep suppresses standard output, so grep won't print anything to the console.
		# The pattern ^\".*\"$ is a regular expression that matches any string that starts and ends with a quotation mark.
		# The ^ symbol represents the start of the line,
		# \" matches a quotation mark,
		# .* matches any character (except a newline) 0 or more times,
		# and $ represents the end of the line.
		# Therefore, this entire line checks if $comment starts and ends with a quotation mark. If it does, the command after the && operator will be executed.
		echo "$comment" | grep -q "^\".*\"$" &&
			# This line assigns a new value to the $comment variable.
			# The echo command again prints out the value of $comment,
			# and this value is piped to the sed command.
			# The -E option enables extended regular expressions in sed.
			# The command s/(^\"|\"$)//g is a sed command that replaces the matched patterns with nothing, effectively deleting them.
			# The pattern (^\"|\"$) matches a quotation mark at the start or end of the line (as explained above).
			# The s at the start of the command stands for "substitute",
			# and the g at the end stands for "global", which means that the command will replace all matches in the line, not just the first one.
			# Therefore, this entire line removes quotation marks at the start or end of $comment.
			comment="$(echo "$comment" | sed -E "s/(^\"|\"$)//g")"
		case "$tag" in
		# If tag is "A", it calls aur_repo_install "$program" "$comment" to install it from the AUR.
		# If tag is "G", it calls git_make_install "$program" "$comment" to clone it from a Git repository and build it.
		# If tag is "P", it calls pip_install "$program" "$comment" to install it with pip, a package manager for Python.
		# If tag is anything else, it calls official_repo_install "$program" "$comment" to install it.
		"A") aur_repo_install "$program" "$comment" ;;
		"G") git_make_install "$program" "$comment" ;;
		"P") pip_install "$program" "$comment" ;;
		*) official_repo_install "$program" "$comment" ;;
		# esac is case spelled backwards.
		# It is the end of the case statement.
		esac
	done </tmp/aegix-programs.csv
}

# gohan_install function:
# Clones a given git repository and places its contents in a specified directory, overwriting any existing files in case of conflicts.
# Input: A string representing the git repository URL ($1) and a string representing the destination directory ($2). An optional branch name can be passed as the third argument ($3).
# First, it creates a temporary directory where the repository is cloned into.
# If the destination directory does not exist, it creates it.
# It then changes the ownership of the temporary and destination directories to the user.
# If no branch name is given, it defaults to the "master" branch.
# Then, it clones the repository into the temporary directory and copies its contents into the destination directory.
gohan_install() {
	whiptail --infobox "Downloading and installing config files..." 7 60
	# This line checks if the third parameter, the branch name, is empty.
	# If it is empty, it sets the branch variable to "master".
	# If it's not empty, it sets branch to the value of $repo_branch.
	[ -z "$3" ] && branch="master" || branch="$repo_branch"
	dir=$(mktemp -d)
	# This line checks if the directory given by $2 (the destination directory) doesn't exist.
	# If it doesn't exist, it creates it using mkdir -p.
	[ ! -d "$2" ] && mkdir -p "$2"
	# This line changes the ownership of the temporary directory and the destination directory to the user.
	chown "$user_name":wheel "$dir" "$2"
	# This line runs the git clone command as the specified user.
	# It changes to the directory specified by $src_repo_dir and clones the git repository given by $1 (repository URL) into the temporary directory $dir.
	# It only clones the specified $branch with a depth of 1 (meaning it only gets the latest commit).
	# The --no-tags option means it won't fetch any tags,
	# and --recursive and --recurse-submodules options are for fetching the contents of submodules too if any exist.
	# The -q option suppresses output from git. The -C option changes the working directory to the specified directory before running the command.
	sudo -u "$user_name" git -C "$src_repo_dir" clone --depth 1 \
		--single-branch --no-tags -q --recursive -b "$branch" \
		--recurse-submodules "$1" "$dir"
	# This line copies the contents of the temporary directory $dir into the destination directory $2.
	# The -r option means it copies directories recursively,
	# and the -f option means it overwrites any existing files in case of conflicts.
	# The -T option means it treats the destination directory as a normal directory, overwriting its contents, if they exist.
	sudo -u "$user_name" cp -rfT "$dir" "$2"
}

# vim_plugin_install function:
# Installs NeoVim plugins.
# First, it creates the required autoload directory in the user's NeoVim configuration directory.
# Then, it downloads the vim-plug plugin manager into the autoload directory.
# After that, it changes the ownership of the NeoVim configuration directory to the user.
# Lastly, it runs NeoVim with a command to install the plugins and then quit.
vim_plugin_install() {
	whiptail --infobox "Installing neovim plugins..." 7 60
	mkdir -p "/home/$user_name/.config/nvim/autoload"
	curl -Ls "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" >  "/home/$user_name/.config/nvim/autoload/plug.vim"
	chown -R "$user_name:wheel" "/home/$user_name/.config/nvim"
	sudo -u "$user_name" nvim -c "PlugInstall|q|q"
}

####
### User Input Functions
####

# get_user_and_pw function:
# Prompts the user for a new username and password.
# Input: User's input for username and password.
# It uses the whiptail dialog utility to interactively prompt the user for a username and password.
# It checks the validity of the provided username and whether the two entered passwords match.
# Output: It sets the 'name' variable with the provided valid username and 'pass1' with the final confirmed password.
# Note: If the user cancels the username prompt, the script will exit. Invalid usernames or mismatched passwords will cause the prompts to repeat.
get_user_and_pw() {
	# Prompts user for new username an password.
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

# user_check function:
# Checks if the user provided in the 'name' variable already exists.
# It uses the id command to check if the 'name' exists as a user in the system.
# If the user exists, it uses whiptail to present a warning and a choice to the user to continue or abort.
# Output: A prompt dialog to the user if the username already exists.
# Note: If the user decides to continue, BARBS will overwrite any conflicting settings/dotfiles for the existing user and update the user password.
user_check() {
	! { id -u "$user_name" >/dev/null 2>&1; } ||
	# ! { id -u "$user_name" >> output.log 2>&1; } ||
		whiptail --title "WARNING" --yes-button "CONTINUE" \
			--no-button "No wait..." \
			--yesno "The user \`$user_name\` already exists on this system. Proceeding will OVERWRITE any conflicting user configuration for this user.\\n\\nUser $user_name's password will also be updated to what you just entered." 14 70
}

# add_user_and_pw function:
# Adds a new user to the system and assigns a password.
# Input: The 'name' and 'pass1' variables.
# Uses the 'useradd' command to add a new user, assigns the user to the 'wheel' group and sets '/bin/zsh' as the default shell.
# If the user already exists, it modifies the user group settings with 'usermod', creates a home directory and assigns ownership.
# It also sets the repository directory ('src_repo_dir') for the user and assigns the necessary permissions.
# Finally, it sets the user password using 'chpasswd'.
# Output: None directly (affects system state by creating a new user).
# Note: Password variables 'pass1' and 'pass2' are unset at the end for the sake of security.
add_user_and_pw() {
	# Adds user `$user_name` with password $pass1.
	whiptail --infobox "Adding user \"$user_name\"..." 7 50
	useradd -m -g wheel -s /bin/zsh "$user_name" >/dev/null 2>&1 ||
	# useradd -m -g wheel -s /bin/zsh "$user_name" >> output.log 2>&1 ||
		usermod -a -G wheel "$user_name" && mkdir -p /home/"$user_name" && chown "$user_name":wheel /home/"$user_name"
	export src_repo_dir="/home/$user_name/.local/src"
	mkdir -p "$src_repo_dir"
	chown -R "$user_name":wheel "$(dirname "$src_repo_dir")"
	echo "$user_name:$pass1" | chpasswd
	unset pass1 pass2
}

####
### Dialog Functions
####

# welcome_message function:
# Displays a welcome message to the user before the start of the script execution.
# Uses 'whiptail' to display a messagebox with the welcome message.
# The message provides a brief explanation of the BARBS script and its purpose.
# There is also a commented out section that can be enabled to display an important note before the script execution begins.
welcome_message() {
	whiptail --title "aegixlinux.org" \
		--msgbox "                    Welcome to BARBS!\\n\\n                    B - Beach \\n                    A - Automation \\n                    R - Routine for \\n                    B - Building \\n                    S - Systems.\\n\\nIf you made it here from the Aegix install.sh script, your base system is installed. We're now inside a chroot, and you're ready to commence with BARBS to set up a graphical environment.\\n\\nBARBS can also be run standalone, in some cases, on top of other distros." 21 60
}

# pre_install_message function:
# Displays a pre-installation message to the user, asking for confirmation to start the script.
# Uses 'whiptail' to display a confirmation dialog.
# The user can choose to continue with the installation or cancel it.
# If the user chooses to cancel, the script clears the terminal and exits.
# This function provides an opportunity for the user to confirm they want to proceed with the installation.
pre_install_message() {
	whiptail --title "Ready?" --yes-button "Let's go!" \
		--no-button "No. Cancel BARBS!" \
		--yesno "Time to get up and stretch a bit.\\n\\nBARBS is about to run its lengthy installation routines.\\n\\nWe'll keep you notified how it's going along the way." 13 60 || {
		clear
		exit 1
	}
}

# finale function:
# Displays a completion message to the user after the script finishes.
# Uses 'whiptail' to display a dialog with the completion message.
# This function assumes that the script has completed successfully.
finale() {
	whiptail --title "All done!" \
		--msgbox "Congrats! You're done with BARBS.\\n\\nIf you got here the traditinoal route from install.sh, you'll be returned to your nice, new system.\\n\\nIf you ran BARBS standalone, you can run startx as your new user. Logging in after reboot will land you in tty1 which will auto-run startx\\n\\nEnjoy\\nAegix" 16 90
}

###
## Main Script Execution
###

####
### Welcome User
####
# If the user exits, display an error message.
welcome_message || error "User exited."

####
### Get User and Password
####
# If the user exits, display an error message.
get_user_and_pw || error "User exited."

####
### Give warning if user already exists.
####
# If the user exits, display an error message.
user_check || error "User exited."

####
### Last Chance to Exit
####
# If the user exits, display an error message.
pre_install_message || error "User exited."

####
### Remaining Setup Does not Require User Input
####
# Refresh Arch keyrings. If there's an error, display a message.
refresh_keys || error "Error automatically refreshing Arch keyring. Consider doing so manually."

####
### Installing Required Packages
####
# Install curl, ca-certificates, base-devel, git, ntp, and zsh. Required for the installation and configuration of other programs.
for x in curl ca-certificates base-devel git zsh; do
	whiptail --title "Installing Required Packages" \
		--infobox "Installing \`$x\` which is required to install and configure other programs." 8 70
	pacman_install "$x"
done

####
### Add User and Set Password
####
# This script calls the add_user_and_pw function. If an error occurs, it will display a custom error message.
add_user_and_pw || error "Error adding username and/or password."

####
### Sudoers File Handling
####
# Check if there is a new sudoers file present. If it is, replace the current sudoers file with it.
# [ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

####
### Grant User Sudo Privileges
####
# Grant the user sudo privileges without requiring a password. This is especially important for building packages from AUR as it needs to be done in a fakeroot environment.
trap 'rm -f /etc/sudoers.d/barbs-temp' HUP INT QUIT TERM PWR EXIT
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/barbs-temp
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

####
### Configure Pacman
####
# Modify the pacman configuration to make it more visually appealing and to enable concurrent downloads.
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf

####
### Set Compilation Flags
####
# Adjust the makepkg.conf file to allow for concurrent compilations equal to the number of processor cores.
sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf

####
### Install AUR helper.
####
# Important for installing AUR programs.
manual_install yay || error "Failed to install AUR helper."

####
### Installing User-Defined Programs
####
# Reads the aegix-programs.csv file and installs each needed program as required.
installation_loop

####
### Install dotfiles
####
# Also remove .git dir and other unnecessary files.
gohan_install "$dot_files_repo" "/home/$user_name" "$repo_branch"
rm -rf "/home/$user_name/.git/" "/home/$user_name/README.md" "/home/$user_name/LICENSE" "/home/$user_name/FUNDING.yml"

####
### Install vim Plugins
####
[ ! -f "/home/$user_name/.config/nvim/autoload/plug.vim" ] && vim_plugin_install

####
### Remove Terminal Beep
####
# First check if loaded
if lsmod | grep "pcspkr" &> /dev/null ; then
    # Remove module if loaded
    echo "pcspkr module is loaded, removing..."
    sudo rmmod pcspkr
	echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf
else
	# Do nothing if not loaded
	echo "pcspkr module is not loaded, these aren't the droids you're looking for.. moving on.."
fi

####
### Make zsh the default shell for the user.
####
chsh -s /bin/zsh "$user_name" >/dev/null 2>&1
# chsh -s /bin/zsh "$user_name" >> output.log 2>&1
sudo -u "$user_name" mkdir -p "/home/$user_name/.cache/zsh/"
sudo -u "$user_name" mkdir -p "/home/$user_name/.config/abook/"
sudo -u "$user_name" mkdir -p "/home/$user_name/.config/mpd/playlists/"

####
### Generate DBUS UUID for Artix Runit
####
# Generate a unique identifier for the dbus instance for the Artix runit system.
mkdir -p /var/lib/dbus/
dbus-uuidgen >/var/lib/dbus/machine-id

####
### System Notifications for Brave on Artix
####
# Configure the system to use the dbus system notifications for the Brave browser on Artix.
echo "export \$(dbus-launch)" >/etc/profile.d/dbus.sh

####
### Enable Tap to Click
####
# Enable the "tap to click" feature for touchpads. This means that a light tap on the touchpad surface will register as a click.
[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
	# Enable left mouse button by tapping
	Option "Tapping" "on"
EndSection' >/etc/X11/xorg.conf.d/40-libinput.conf

####
### User Access and Privileges
####
# NOTE: The commented lines below provide a less-privileged access model.
# In this script, we do not wish to limit the user's access to root privileges.
# If you need to implement the less-privileged model, uncomment the lines and
# work on /etc/sudoers (use sudo visudo). Pay special attention to what is included inherently in /etc/sudoers.d/

# echo "%wheel ALL=(ALL:ALL) ALL" >/etc/sudoers.d/00-barbs-wheel-can-sudo
# echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/brightnessctl,/usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/pacman -Syyuw --noconfirm,/usr/bin/pacman -S -u -y --config /etc/pacman.conf --,/usr/bin/pacman -S -y -u --config /etc/pacman.conf --" >/etc/sudoers.d/01-barbs-cmds-without-password

####
### Visudo Configuration
####
# Enable all users in the wheel group to execute any command without a password.
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
# No restriction to root access
# Either know what you're doing with root or don't use it at all.

# Set nvim as the default editor for sudoers file.
echo "Defaults editor=/usr/bin/nvim" >/etc/sudoers.d/02-barbs-visudo-editor

####
### Create basic dirs
####
mkdir -p /home/$user_name/Downloads /home/$user_name/Documents /home/$user_name/Pictures /home/$user_name/Music /home/$user_name/Videos/obs /home/$user_name/code /home/$user_name/ss /home/$user_name/Applications/vs-code-insider
chown -R $user_name:wheel /home/$user_name/*

## update bg symlink to point to user selection
sudo ln -sf /root/aegix-forest.png bg

# Uncomment to use dmesg without root privileges
# mkdir -p /etc/sysctl.d
# echo "kernel.dmesg_restrict = 0" > /etc/sysctl.d/dmesg.conf

# ####
# ### Auto-Login for LUKS
# ####
# # This section is for enabling auto-login.

# # Ask the user if they want to enable auto-login.
# read -p "Do you want to enable auto-login for LUKS? (y/n): " autologin_choice

# # Process the user's response.
# case $autologin_choice in
#   y|Y)
#     # If they chose 'yes', enable auto-login.
#     sed -i "s/^GETTY_ARGS=\"\(.*\)\"/GETTY_ARGS=\"\1 --autologin $user_name\"/" /etc/runit/sv/agetty-tty1/conf
#     echo "Auto-login enabled."
#     ;;
#   *)
#     # If they chose anything else, do not enable auto-login.
#     echo "Auto-login not enabled."
#     ;;
# esac

####
### Installation Completion
####
# Display the final installation complete message.
finale
