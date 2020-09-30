#!/bin/bash

## Prerequisites:
# Working duplicacy repository located at /Users. In other words, running 
# "duplicacy backup" in /Users shall work.


# Configuration 
readonly CPU_LIMIT_AC=40
readonly CPU_LIMIT_BATTERY=10

## Acceptable values are Latest, Stable, or specific version
# readonly REQUESTED_CLI_VERSION=Latest
# readonly REQUESTED_CLI_VERSION=Stable
readonly REQUESTED_CLI_VERSION="2.7.0"

readonly LAUNCHD_BACKUP_SCHEDULE='
	<key>StartCalendarInterval</key>
	<dict>
		<key>Minute</key>
		<integer>0</integer>
	</dict>
'

## Should not need to modify anything below this line.

# Setup
readonly REPOSITORY_ROOT='/Users'
readonly DOWNLOAD_ROOT='https://github.com/gilbertchen/duplicacy/releases/download'
readonly LOGS_PATH='/Library/Logs/Duplicacy'
readonly LAUNCHD_BACKUP_NAME='com.duplicacy.backup'

# Derivatives
readonly DUPLICACY_CONFIG_DIR="${REPOSITORY_ROOT}/.duplicacy"
readonly LAUNCHD_BACKUP_PLIST="/Library/LaunchDaemons/${LAUNCHD_BACKUP_NAME}.plist"

## Helpers
# Verify that utilities required are available
function check_utilities_full()
{
	local error_code=0
	for cmd in wget jq curl
	do
		if ! command -v $cmd > /dev/null 
		then  
			printf "Missing %s\n" "$cmd";
			error_code=1;
		fi
	done 
	return $error_code
}

function check_utilities_lite()
{
	local error_code=0
	for cmd in wget 
	do
		if ! command -v $cmd > /dev/null 
		then  
			printf "Missing %s\n" "$cmd";
			error_code=1;
		fi
	done 
	return $error_code
}

## Download duplicacy if needed
#
function update_duplicacy_binary()
{
	mkdir -p "${DUPLICACY_CONFIG_DIR}"
	
	case "${REQUESTED_CLI_VERSION}" in 
	Stable|stable) 
		check_utilities_full || return $?
		SELECTED_VERSION=$(curl -s 'https://duplicacy.com/latest_cli_version' |jq -r '.stable' 2>/dev/null) 
		;;
	Latest|latest) 
		check_utilities_full || return $?
		SELECTED_VERSION=$(curl -s 'https://duplicacy.com/latest_cli_version' |jq -r '.latest' 2>/dev/null) 
		;;
	*) 
		check_utilities_lite || return $?
		if [[ "${REQUESTED_CLI_VERSION}"  =~ ^[0-9.]+$ ]] ; then 
			SELECTED_VERSION="${REQUESTED_CLI_VERSION}" 
		else 
			echo "Unrecognised update channel ${REQUESTED_CLI_VERSION}. Defaulting to Stable"; 
			SELECTED_VERSION=$(curl -s 'https://duplicacy.com/latest_cli_version' |jq -r '.stable' 2>/dev/null) 
		fi 
		;;
	esac
	
	LOCAL_EXECUTABLE_NAME="${DUPLICACY_CONFIG_DIR}/duplicacy_osx_x64_${SELECTED_VERSION}"

	if [ -f "${LOCAL_EXECUTABLE_NAME}" ] 
	then
		echo "Version ${SELECTED_VERSION} is up to date"
	else
		DOWNLOAD_URL="${DOWNLOAD_ROOT}/v${SELECTED_VERSION}/duplicacy_osx_x64_${SELECTED_VERSION}"
		if wget -O "${LOCAL_EXECUTABLE_NAME}" "${DOWNLOAD_URL}" ; then 
			chmod u=rwx,g=rx,o=rx "${LOCAL_EXECUTABLE_NAME}"
			echo "Updated to ${SELECTED_VERSION}"
		else
			echo "Could not download ${DOWNLOAD_URL}"
			rm -f "${LOCAL_EXECUTABLE_NAME}"
		return 1
		fi
	fi 
	return 0
}

## Write out the launch plists
function prepare_launchd_backup_plist()
{
	echo "Writing out ${LAUNCHD_BACKUP_PLIST}"
	mkdir -p ${LOGS_PATH}

	cat > "${LAUNCHD_BACKUP_PLIST}" <<- EOF
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
	    <key>StandardOutPath</key>
	    <string>${LOGS_PATH}/${LAUNCHD_BACKUP_NAME}.out.log</string>

	    <key>StandardErrorPath</key>
	    <string>${LOGS_PATH}/${LAUNCHD_BACKUP_NAME}.err.log</string>

        <key>KeepAlive</key>
        <false/>

	    <key>Label</key>
	    <string>${LAUNCHD_BACKUP_NAME}</string>

	    <key>WorkingDirectory</key>
	    <string>${REPOSITORY_ROOT}</string>

	    <key>Program</key>
	    <string>${DUPLICACY_CONFIG_DIR}/backup.sh</string>

	    ${LAUNCHD_BACKUP_SCHEDULE}
	
	</dict>
	</plist>
	EOF
	return 0
}
 
## Write out throttler scripts
#
function prepare_duplicacy_scripting()
{
	BACKUP="${DUPLICACY_CONFIG_DIR}/backup.sh"
	echo "Writing out ${BACKUP}"


	cat > "${BACKUP}" <<- EOF
	#!/bin/bash
	CPU_LIMIT_CORE_AC=${CPU_LIMIT_AC}
	CPU_LIMIT_CORE_BATTERY=${CPU_LIMIT_BATTERY}
	DUPLICASY_CLI_PATH="${LOCAL_EXECUTABLE_NAME}"
	EOF

	cat >> "${BACKUP}" <<- 'EOF'
	case "$(pmset -g batt | grep 'Now drawing from')" in
	*Battery*) CPU_LIMIT_CORE=${CPU_LIMIT_CORE_BATTERY} ;;
	*)		   CPU_LIMIT_CORE=${CPU_LIMIT_CORE_AC} ;;
	esac

	function terminator() {
	    kill -TERM "${duplicacy}" 
	    kill -TERM "${throttler}" 
	}

	trap terminator SIGHUP SIGINT SIGQUIT SIGTERM EXIT

	"${DUPLICASY_CLI_PATH}" backup &
	duplicacy=$!
	/usr/local/bin/cpulimit --limit=${CPU_LIMIT_CORE} --include-children --pid=${duplicacy} &
	throttler=$!

	wait ${throttler}

	EOF

    chmod +x "${BACKUP}"|| exit $?
    return 0;
}

if [[ $(id -u) != 0 ]]; then
	sudo -p 'Restarting as root, password: ' bash $0 "$@"
	exit $?
fi

if [ ! -f "${DUPLICACY_CONFIG_DIR}/preferences" ] ; then 
	echo "Please initialize duplicacy repository at ${REPOSITORY_ROOT} first."
	exit 2; 
fi 

echo "Stopping and unloading existing daemon"
launchctl stop "${LAUNCHD_BACKUP_NAME}" 2>/dev/null
launchctl unload "${LAUNCHD_BACKUP_PLIST}" 2>/dev/null

update_duplicacy_binary || exit $?
prepare_duplicacy_scripting || exit $?
prepare_launchd_backup_plist || exit $?


echo Loading the daemon "${LAUNCHD_BACKUP_NAME}"
launchctl load -w "${LAUNCHD_BACKUP_PLIST}" || exit $?

echo Success.
