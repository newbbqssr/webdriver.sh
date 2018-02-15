#!/bin/bash
#
# webdriver.sh - bash script for managing Nvidia's web drivers
# Copyright © 2017-2018 vulgo
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#

SCRIPT_VERSION="1.0.18"

R='\e[0m'	# no formatting
B='\e[1m'	# bold
U='\e[4m'	# underline

if ! /usr/bin/sw_vers -productVersion | /usr/bin/grep "10.13" > /dev/null 2>&1; then
	printf 'Unsupported macOS version'
	exit 1
fi


if ! MAC_OS_BUILD=$(/usr/bin/sw_vers -buildVersion); then
	printf 'sw_vers error\n'
	exit $?
fi

TMP_DIR=$(/usr/bin/mktemp -dt webdriver)
REMOTE_UPDATE_PLIST="https://gfestage.nvidia.com/mac-update"
CHANGES_MADE=false
RESTART_REQUIRED=true
NO_CACHE_UPDATE_OPTION=false
REINSTALL_OPTION=false
REINSTALL_MESSAGE=false
SYSTEM_OPTION=false
YES_OPTION=false
DOWNLOADED_UPDATE_PLIST="${TMP_DIR}/nvwebupdates.plist"
DOWNLOADED_PKG="${TMP_DIR}/nvweb.pkg"
EXTRACTED_PKG_DIR="${TMP_DIR}/nvwebinstall"
SQL_QUERY_FILE="${TMP_DIR}/nvweb.sql"
SQL_DEVELOPER_NAME="NVIDIA Corporation"
SQL_TEAM_ID="6KR3T733EC"
INSTALLED_VERSION="/Library/Extensions/GeForceWeb.kext/Contents/Info.plist"
DRIVERS_DIR_HINT="NVWebDrivers.pkg"
MOD_INFO_PLIST_PATH="/Library/Extensions/NVDAStartupWeb.kext/Contents/Info.plist"
EGPU_INFO_PLIST_PATH="/Library/Extensions/NVDAEGPUSupport.kext/Contents/Info.plist"
MOD_KEY=":IOKitPersonalities:NVDAStartup:NVDARequiredOS"
BREW_PREFIX=$(brew --prefix 2> /dev/null)
HOST_PREFIX="/usr/local"
BASENAME=$(/usr/bin/basename "$0")
RAW_ARGS="$@"
(( CACHES_ERROR = 0 ))
(( COMMAND_COUNT = 0 ))

if [[ $BASENAME =~ "system-update" ]]; then
	[[ $1 != "-u" ]] && exit 1
	[[ -z $2 ]] && exit 1
	set -- "-Sycu" "$2"
fi

function usage() {
	printf 'Usage: %s [-f] [-c] [-u URL|-r|-m [BUILD]|-p]\n' "$BASENAME"
	printf '          -u URL        install driver package at URL, no version checks\n'
	printf '          -r            uninstall drivers\n'
	printf "          -m [BUILD]    modify the current driver's NVDARequiredOS\n"
	printf '          -f            re-install the current drivers\n'
        printf "          -c            don't update caches\n"
	printf '          -p            download the updates property list and exit\n'
}

function version() {
	printf 'webdriver.sh %s Copyright © 2017-2018 vulgo\n' "$SCRIPT_VERSION"
	printf 'This is free software: you are free to change and redistribute it.\n'
	printf 'There is NO WARRANTY, to the extent permitted by law.\n'
	printf 'See the GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>\n'
}

while getopts ":hvpu:rm:cfSy" OPTION; do
	case $OPTION in
	"h")
		usage
		exit 0;;
	"v")
		version
		exit 0;;
	"p")
		COMMAND="GET_PLIST_AND_EXIT"
		(( COMMAND_COUNT += 1 ));;
	"u")
		COMMAND="USER_PROVIDED_URL"
		REMOTE_URL="$OPTARG"
		(( COMMAND_COUNT += 1 ));;
	"r")
		COMMAND="UNINSTALL_DRIVERS_AND_EXIT"
		(( COMMAND_COUNT += 1 ));;
	"m")
		MOD_REQUIRED_OS="$OPTARG"
		COMMAND="SET_REQUIRED_OS_AND_EXIT"
		(( COMMAND_COUNT += 1 ));;
	"c")
		NO_CACHE_UPDATE_OPTION=true
		RESTART_REQUIRED=false;;
	"f")
		REINSTALL_OPTION=true;;
	"S")	
		SYSTEM_OPTION=true;;
	"y")
		YES_OPTION=true;;
	"?")
		printf 'Invalid option: -%s\n' "$OPTARG"
		usage
		exit 1;;
	":")
		if [[ $OPTARG == "m" ]]; then
			MOD_REQUIRED_OS="$MAC_OS_BUILD"
			COMMAND="SET_REQUIRED_OS_AND_EXIT"
			(( COMMAND_COUNT += 1 ))
		else
			printf 'Missing parameter for -%s\n' "$OPTARG"
			usage
			exit 1
		fi;;
	esac
	if (( COMMAND_COUNT > 1)); then
		printf 'Too many options\n'
		usage
		exit 1
	fi
done

function silent() {
	# silent $@: args... 
	"$@" > /dev/null 2>&1
	return $?
}

function error() {
	# error $1: message, $2: exit_code
	delete_temporary_files
	if [[ -z $2 ]]; then
		printf '%bError%b: %s\n' "$U" "$R" "$1"
	else
		printf '%bError%b: %s (%s)\n' "$U" "$R" "$1" "$2"
	fi
	if $CHANGES_MADE; then
		unset_nvram
	else
		printf 'No changes were made\n'
	fi
	exit 1
}

function delete_temporary_files() {
	silent rm -rf "$TMP_DIR"
}

function exit_ok() {
	delete_temporary_files
	exit 0
}

# COMMAND GET_PLIST_AND_EXIT

if [[ $COMMAND == "GET_PLIST_AND_EXIT" ]]; then
	(( i = 0 ))
	DOWNLOAD_PATH=~/Downloads/NvidiaUpdates
	while (( i < 49 )); do
		if (( i == 0 )); then
			DESTINATION="${DOWNLOAD_PATH}.plist"
		else
			DESTINATION="${DOWNLOAD_PATH}-${i}.plist"
		fi
		if ! [[ -f "$DESTINATION" ]]; then
			break
		fi
		(( i += 1 ))
	done
	printf '%bDownloading...%b\n' "$B" "$R"
	/usr/bin/curl -s --connect-timeout 15 -m 45 -o "$DESTINATION" "$REMOTE_UPDATE_PLIST" \
		|| error "Couldn't get updates data from Nvidia" $?
	printf '%s\n' "$DESTINATION"
	/usr/bin/open -R "$DESTINATION"
	delete_temporary_files
	exit 0
fi

# Check root

if [[ $(/usr/bin/id -u) != "0" ]]; then
	printf 'Run it as root: sudo %s %s' "$BASENAME" "$RAW_ARGS"
	exit 0
fi

# Check SIP/file system permissions

if ! /usr/bin/touch /System; then
	printf 'Permission denied.\n'
	printf 'Ensure that SIP is disabled.\n'
	printf 'See: csrutil(8)\n'
	exit 1
fi

function bye() {
	printf 'Complete.'
	if $RESTART_REQUIRED; then
		printf ' You should reboot now.\n'
	else
		printf '\n'
	fi
	exit $CACHES_ERROR
}

function warning() {
	# warning $1: message
	printf '%bWarning%b: %s\n' "$U" "$R" "$1" 
}

function etc() {
	# exec_conf $1: path_to_script $2: arg_1
	if [[ -f "${BREW_PREFIX}${1}" ]]; then
		"${BREW_PREFIX}${1}" "$2"
	elif [[ -f "${HOST_PREFIX}${1}" ]]; then
		"${HOST_PREFIX}${1}" "$2"
	fi
}

function post_install() {
	# post_install $1: extracted_package_dir
	local SCRIPT="/etc/webdriver.sh/post-install.conf"
	etc "$SCRIPT" "$1"
}

function uninstall_extra() {
	local SCRIPT="/etc/webdriver.sh/uninstall.conf"
	etc "$SCRIPT"
}

function uninstall_drivers() {
	local EGPU_DEFAULT="/Library/Extensions/NVDAEGPUSupport.kext"
	local EGPU_RENAMED="/Library/Extensions/EGPUSupport.kext"
	local REMOVE_LIST="/Library/Extensions/GeForce* \
		/Library/Extensions/NVDA* \
		/System/Library/Extensions/GeForce*Web* \
		/System/Library/Extensions/NVDA*Web*"
	# Remove drivers
	silent mv "$EGPU_DEFAULT" "$EGPU_RENAMED"
	silent rm -rf $REMOVE_LIST
	# Remove driver flat package receipt
	silent pkgutil --forget com.nvidia.web-driver
	silent mv "$EGPU_RENAMED" "$EGPU_DEFAULT"
	uninstall_extra
}

function caches_error() {
	# caches_error $1: warning_message
	warning "$1"
	(( CACHES_ERROR = 1 ))
}

function update_caches() {
	if $NO_CACHE_UPDATE_OPTION; then
		warning "Caches are not being updated"
		return 0
	fi
	printf '%bUpdating caches...%b\n' "$B" "$R"
	local PLK="Created prelinked kernel"
	local SLE="caches updated for /System/Library/Extensions"
	local LE="caches updated for /Library/Extensions"
	local RESULT=
	RESULT=$(/usr/sbin/kextcache -v 2 -i / 2>&1)
	silent /usr/bin/grep "$PLK" <<< "$RESULT" \
		|| caches_error "There was a problem creating the prelinked kernel"
	silent /usr/bin/grep "$SLE" <<< "$RESULT" \
		|| caches_error "There was a problem updating directory caches for /S/L/E"
	silent /usr/bin/grep "$LE" <<< "$RESULT" \
		|| caches_error "There was a problem updating directory caches for /L/E"
	if (( CACHES_ERROR != 0 )); then
		printf '\nTo try again use:\n%bsudo kextcache -i /%b\n\n' "$B" "$R"
		RESTART_REQUIRED=false
	fi	 
}

function ask() {
	# ask $1: message
	local ASK=
	printf '%b%s%b' "$B" "$1" "$R"
	read -n 1 -srp " [y/N]" ASK
	printf '\n'
	if [[ $ASK == "y" || $ASK == "Y" ]]; then
		return 0
	else
		return 1
	fi
}

function plist_read_error() {
	error "Couldn't read a required value from a property list"
}

function plist_write_error() {
	error "Couldn't set a required value in a property list"
}

function plistb() {
	# plistb $1: command, $2: file
	local RESULT=
	if ! [[ -f "$2" ]]; then
		return 1;
	else 
		if ! RESULT=$(/usr/libexec/PlistBuddy -c "$1" "$2" 2> /dev/null); then
			return 1; fi
	fi
	[[ $RESULT ]] && printf "%s" "$RESULT"
	return 0
}

function sha512() {
	# checksum $1: file
	local RESULT=
	RESULT=$(/usr/bin/shasum -a 512 "$1" | /usr/bin/awk '{print $1}')
	[[ $RESULT ]] && printf '%s' "$RESULT"
}

function set_nvram() {
	/usr/sbin/nvram nvda_drv=1%00
}

function unset_nvram() {
	/usr/sbin/nvram -d nvda_drv
}

function set_required_os() {
	# set_required_os $1: target_version
	local RESULT=
	local BUILD="$1"
	RESULT=$(plistb "Print $MOD_KEY" "$MOD_INFO_PLIST_PATH") || plist_read_error
	if [[ $RESULT == "$BUILD" ]]; then
		printf 'NVDARequiredOS already set to %s\n' "$BUILD"
	else 
		CHANGES_MADE=true
		printf '%bSetting NVDARequiredOS to %s...%b\n' "$B" "$BUILD" "$R"
		plistb "Set $MOD_KEY $BUILD" "$MOD_INFO_PLIST_PATH" || plist_write_error
	fi
	if [[ -f $EGPU_INFO_PLIST_PATH ]]; then
		RESULT=$(plistb "Print $MOD_KEY" "$EGPU_INFO_PLIST_PATH") || plist_read_error
		if [[ $RESULT == "$BUILD" ]]; then
			printf 'Found NVDAEGPUSupport.kext, already set to %s\n' "$BUILD"
		else
			CHANGES_MADE=true
			printf '%bFound NVDAEGPUSupport.kext, setting NVDARequiredOS to %s...%b\n' "$B" "$BUILD" "$R"
			plistb "Set $MOD_KEY $BUILD" "$EGPU_INFO_PLIST_PATH"  || plist_write_error
		fi
	fi
}

function check_required_os() {
	$YES_OPTION && return 0
	local RESULT=
	if [[ -f $MOD_INFO_PLIST_PATH ]]; then
		RESULT=$(plistb "Print $MOD_KEY" "$MOD_INFO_PLIST_PATH") || plist_read_error
		if [[ $RESULT != "$MAC_OS_BUILD" ]]; then
			ask "Modify installed driver for current macOS version?" || return 0
			set_required_os "$MAC_OS_BUILD"
			RESTART_REQUIRED=true
			return 1
		fi
	fi
}

# COMMAND SET_REQUIRED_OS_AND_EXIT

if [[ $COMMAND == "SET_REQUIRED_OS_AND_EXIT" ]]; then
	(( ERROR = 0 ))
	if [[ ! -f $MOD_INFO_PLIST_PATH ]]; then
		printf 'Nvidia driver not found\n'
		(( ERROR = 1 ))
	else
		set_required_os "$MOD_REQUIRED_OS"
	fi
	if $CHANGES_MADE; then
		update_caches
	else
		printf 'No changes were made\n'
	fi
	if [[ $ERROR == 0 ]]; then
		set_nvram
	else
		unset_nvram
	fi
	delete_temporary_files
	exit $ERROR
fi

# COMMAND UNINSTALL_DRIVERS_AND_EXIT

if [[ $COMMAND == "UNINSTALL_DRIVERS_AND_EXIT" ]]; then
	ask "Uninstall Nvidia web drivers?"
	printf '%bRemoving files...%b\n' "$B" "$R"
	CHANGES_MADE=true
	uninstall_drivers
	update_caches
	unset_nvram
	bye
fi

function installed_version() {
	if [[ -f $INSTALLED_VERSION ]]; then
		GET_INFO_STRING=$(plistb "Print :CFBundleGetInfoString" "$INSTALLED_VERSION")
		GET_INFO_STRING="${GET_INFO_STRING##* }"
		printf "$GET_INFO_STRING"
	fi
}

function sql_add_kext() {
	# sql_add_kext $1:bundle_id
	printf 'insert or replace into kext_policy '
	printf '(team_id, bundle_id, allowed, developer_name, flags) '
	printf 'values (\"%s\",\"%s\",1,\"%s\",1);\n' "$SQL_TEAM_ID" "$1" "$SQL_DEVELOPER_NAME"
} >> "$SQL_QUERY_FILE"

# UPDATER/INSTALLER

if [[ $COMMAND != "USER_PROVIDED_URL" ]]; then

	# No URL specified, get installed web driver verison
	VERSION=$(installed_version)

	# Get updates file
	printf '%bChecking for updates...%b\n' "$B" "$R"
	/usr/bin/curl -s --connect-timeout 15 -m 45 -o "$DOWNLOADED_UPDATE_PLIST" "$REMOTE_UPDATE_PLIST" \
		|| error "Couldn't get updates data from Nvidia" $?

	# Check for an update
	c=$(/usr/bin/grep -c "<dict>" "$DOWNLOADED_UPDATE_PLIST")
	(( c -= 1, i = 0 ))
	while (( i < c )); do
		if ! REMOTE_MAC_OS_BUILD=$(plistb "Print :updates:${i}:OS" "$DOWNLOADED_UPDATE_PLIST"); then
			unset REMOTE_MAC_OS_BUILD
			break
		fi
		if [[ $REMOTE_MAC_OS_BUILD == "$MAC_OS_BUILD" ]]; then
			if ! REMOTE_URL=$(plistb "Print :updates:${i}:downloadURL" "$DOWNLOADED_UPDATE_PLIST"); then
				unset REMOTE_URL; fi
			if ! REMOTE_VERSION=$(plistb "Print :updates:${i}:version" "$DOWNLOADED_UPDATE_PLIST"); then
				unset REMOTE_VERSION; fi
			if ! REMOTE_CHECKSUM=$(plistb "Print :updates:${i}:checksum" "$DOWNLOADED_UPDATE_PLIST"); then
				unset REMOTE_CHECKSUM; fi
			break
		fi
		(( i += 1 ))
	done;
	
	# Determine next action
	if [[ -z $REMOTE_URL || -z $REMOTE_VERSION ]]; then
		# No driver available, or error during check, exit
		printf 'No driver available for %s\n' "$MAC_OS_BUILD"
		check_required_os
		if $CHANGES_MADE; then
			update_caches
			set_nvram
		fi
		exit_ok
	elif [[ $REMOTE_VERSION == "$VERSION" ]]; then
		# Latest already installed, exit
		printf '%s for %s already installed\n' "$REMOTE_VERSION" "$MAC_OS_BUILD"
		if ! $REINSTALL_OPTION; then
			printf 'To re-install use -f\n' "$BASENAME"
			check_required_os
			if $CHANGES_MADE; then
				update_caches
				set_nvram
			fi
			exit_ok
		fi
		REINSTALL_MESSAGE=true
	else
		# Found an update, proceed to installation
		printf 'Web driver %s available...\n' "$REMOTE_VERSION"
	fi

else
	
	# Invoked with -u option, proceed to installation
	printf 'URL: %s\n' "$REMOTE_URL"
	RESTART_REQUIRED=false
	
fi

# Prompt install y/n

if ! $YES_OPTION; then
	if $REINSTALL_MESSAGE; then
		ask "Re-install?" || exit_ok
	else
		ask "Install?" || exit_ok
	fi
fi

# Check URL

REMOTE_HOST=$(printf '%s' "$REMOTE_URL" | /usr/bin/awk -F/ '{print $3}')
if ! silent /usr/bin/host "$REMOTE_HOST"; then
	if [[ $COMMAND == "USER_PROVIDED_URL" ]]; then
		error "Unable to resolve host, check your URL"; fi
	REMOTE_URL="https://images.nvidia.com/mac/pkg/"
	REMOTE_URL+="${REMOTE_VERSION%%.*}"
	REMOTE_URL+="/WebDriver-${REMOTE_VERSION}.pkg"
fi
HEADERS=$(/usr/bin/curl -I "$REMOTE_URL" 2>&1) \
	|| error "Failed to download HTTP headers"
silent /usr/bin/grep "octet-stream" <<< "$HEADERS" \
	|| warning "Unexpected HTTP content type"
if [[ $COMMAND != "USER_PROVIDED_URL" ]]; then
	printf 'URL: %s\n' "$REMOTE_URL"; fi

# Download

printf '%bDownloading package...%b\n' "$B" "$R"
/usr/bin/curl --connect-timeout 15 -# -o "$DOWNLOADED_PKG" "$REMOTE_URL" \
	|| error "Failed to download package" $?

# Checksum

LOCAL_CHECKSUM=$(sha512 "$DOWNLOADED_PKG")
if [[ $REMOTE_CHECKSUM ]]; then
	if [[  $LOCAL_CHECKSUM == "$REMOTE_CHECKSUM" ]]; then
		printf 'SHA512: Verified\n'
	else
		error "SHA512 verification failed"
	fi
else
	printf 'SHA512: %s\n' "$LOCAL_CHECKSUM"
fi


# Extract

printf '%bExtracting...%b\n' "$B" "$R"
/usr/sbin/pkgutil --expand "$DOWNLOADED_PKG" "$EXTRACTED_PKG_DIR" \
	|| error "Failed to extract package" $?
DIRS=("$EXTRACTED_PKG_DIR"/*"$DRIVERS_DIR_HINT")
if [[ ${#DIRS[@]} = 1 ]] && ! [[ ${DIRS[0]} =~ "*" ]]; then
        PAYLOAD_BASE_DIR=${DIRS[0]}
else
        error "Failed to find pkgutil output directory"
fi
cd "$PAYLOAD_BASE_DIR" || error "Failed to find pkgutil output directory" $?
/usr/bin/gunzip -dc < ./Payload > ./tmp.cpio \
	|| error "Failed to extract package" $?
/usr/bin/cpio -i < ./tmp.cpio \
	|| error "Failed to extract package" $?
if [[ ! -d ./Library/Extensions || ! -d ./System/Library/Extensions ]]; then
	error "Unexpected directory structure after extraction"; fi
	
# Make SQL

printf '%bApproving kexts...%b\n' "$B" "$R"
cd "$PAYLOAD_BASE_DIR" || error "Failed to find payload base directory" $?
KEXT_INFO_PLISTS=(./Library/Extensions/*.kext/Contents/Info.plist)
for PLIST in "${KEXT_INFO_PLISTS[@]}"; do
	BUNDLE_ID=$(plistb "Print :CFBundleIdentifier" "$PLIST") || plist_read_error
	[[ $BUNDLE_ID ]] && sql_add_kext "$BUNDLE_ID"
done
sql_add_kext "com.nvidia.CUDA"

CHANGES_MADE=true

# Allow kexts

/usr/bin/sqlite3 /var/db/SystemPolicyConfiguration/KextPolicy < "$SQL_QUERY_FILE" \
	|| warning "sqlite3 exit code $?, extensions may not be loadable"

# Install

printf '%bInstalling...%b\n' "$B" "$R"
uninstall_drivers
cd "$PAYLOAD_BASE_DIR" || error "Failed to find payload base directory" $?
cp -r ./Library/Extensions/* /Library/Extensions
cp -r ./System/Library/Extensions/* /System/Library/Extensions
post_install "$PAYLOAD_BASE_DIR"

# Update caches and exit

check_required_os
update_caches
set_nvram
delete_temporary_files
if $SYSTEM_OPTION; then
	printf '%bSystem update...%b\n' "$B" "$R"
	silent /usr/sbin/softwareupdate -ir
fi
bye
