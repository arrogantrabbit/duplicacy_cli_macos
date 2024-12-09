#!/bin/bash

## Prerequisites:
# - HomeBrew
# - Working duplicacy repository located at /Library/Duplicacy and pointing to /Users. 
#   In other words, running "cd /Library/Duplicacy && sudo duplicacy backup" shall work.

## Overridable configuration
 
# CPU limit when on AC power
: "${CPU_LIMIT_AC:="40"}"

# CPU limit when on Battery power
: "${CPU_LIMIT_BATTERY:="10"}"

# AC/Battery check interval in sectons
: "${CHECK_POWER_SOURCE_EVERY:="60"}"

# Duplicacy version
# Acceptable values are Latest, Stable, Custom, or specific version
# REQUESTED_CLI_VERSION="2.7.2"
# EQUESTED_CLI_VERSION=Latest
: "${REQUESTED_CLI_VERSION:="Stable"}"
# REQUESTED_CLI_VERSION=Custom
: "${DUPLICACY_CUSTOM_BINARY:="/Library/Duplicacy/duplicacy_osx_custom"}"


: "${DUPLICACY_GLOBAL_OPTIONS=""}"
: "${DUPLICACY_BACKUP_OPTIONS="-vss -threads 4"}"
# launchd schedule to run backup task. see man launchd.plist for configuration help 
# Run backup hourly

: "${LAUNCHD_BACKUP_SCHEDULE:="$(cat <<- EOF
	    <key>StartCalendarInterval</key>
	    <dict>
	        <key>Minute</key>
	        <integer>0</integer>
	    </dict>
EOF
)"}"


# Retention
# After two weeks keep a version every day
# After 90 days keep a version every week
# After one year keep a version every month
: "${DUPLICACY_PRUNE_OPTIONS=" -keep 31:360 -keep 7:90 -keep 1:14 -all"}"
# Run prune weekly
: "${LAUNCHD_PRUNE_SCHEDULE:="$(cat <<- EOF
	    <key>StartCalendarInterval</key>
	    <dict>
	        <key>Weekday</key>
	        <integer>0</integer>
	        <key>Hour</key>
	        <integer>0</integer>
	        <key>Minute</key>
	        <integer>0</integer>
	    </dict>
EOF
)"}"

# Where duplicacy is initialized 
: "${DUPLICACY_CONFIG_ROOT:="/Library/Duplicacy"}"

## ---------------------------------------------------
## Should not need to modify anything below this line.

# Setup
readonly DOWNLOAD_ROOT='https://github.com/gilbertchen/duplicacy/releases/download'
readonly LOGS_PATH='/Library/Logs/Duplicacy'
readonly LAUNCHD_BACKUP_NAME='com.duplicacy.backup'
readonly HELPER_BACKUP_APP_NAME='Duplicacy-Backup.app'
readonly LAUNCHD_PRUNE_NAME='com.duplicacy.prune'

# Derivatives
readonly LAUNCHD_BACKUP_PLIST="/Library/LaunchDaemons/${LAUNCHD_BACKUP_NAME}.plist"
readonly LAUNCHD_PRUNE_PLIST="/Library/LaunchDaemons/${LAUNCHD_PRUNE_NAME}.plist"

## Helpers
# Verify that utilities required are available
#
function check_utilities()
{
	local error_code=0
	for cmd in "$@"
	do
		if ! command -v "$cmd" > /dev/null
		then
			printf "%12s Missing\n" "$cmd"
			error_code=1;
		else
			printf "%12s OK\n" "$cmd"
		fi
	done
	return $error_code
}

## Download duplicacy if needed
#
function update_duplicacy_binary()
{
	# Determine required version
	case "${REQUESTED_CLI_VERSION}" in 
	Stable|stable) 
		check_utilities platypus cpulimit wget jq curl || return $?
		SELECTED_VERSION=$(curl -s 'https://duplicacy.com/latest_cli_version' |jq -r '.stable' 2>/dev/null) 
		;;
	Latest|latest) 
		check_utilities platypus cpulimit wget jq curl || return $?
		SELECTED_VERSION=$(curl -s 'https://duplicacy.com/latest_cli_version' |jq -r '.latest' 2>/dev/null) 
		;;
	Custom|custom) 
		check_utilities platypus cpulimit || return $?
		;;
	*) 
		check_utilities platypus cpulimit wget || return $?
		if [[ "${REQUESTED_CLI_VERSION}"  =~ ^[0-9.]+$ ]] ; then 
			SELECTED_VERSION="${REQUESTED_CLI_VERSION}" 
		else 
			echo "Unrecognised update channel ${REQUESTED_CLI_VERSION}. Defaulting to Stable"; 
			SELECTED_VERSION=$(curl -s 'https://duplicacy.com/latest_cli_version' |jq -r '.stable' 2>/dev/null) 
		fi 
		;;
	esac

	MACHINE_ARCH=$(uname -m)

	case "${REQUESTED_CLI_VERSION}" in 
	Custom|custom) 
		DUPLICACY_CLI_PATH="${DUPLICACY_CUSTOM_BINARY}"
		if [ -f "${DUPLICACY_CLI_PATH}" ] 
		then
			echo "Custom binary ${DUPLICACY_CLI_PATH} exists"
		else
			echo "Duplicacy custom binary ${DUPLICACY_CLI_PATH} does not exist"
			return 1
		fi
		;;
	*)
		DUPLICACY_CLI_PATH="${DUPLICACY_CONFIG_ROOT}/duplicacy_osx_${MACHINE_ARCH}_${SELECTED_VERSION}"
		if [ -f "${DUPLICACY_CLI_PATH}" ] 
		then
			echo "Version ${SELECTED_VERSION} is up to date"
		else
			DOWNLOAD_URL="${DOWNLOAD_ROOT}/v${SELECTED_VERSION}/duplicacy_osx_${MACHINE_ARCH}_${SELECTED_VERSION}"
			if wget -O "${DUPLICACY_CLI_PATH}" "${DOWNLOAD_URL}" ; then 
				chmod u=rwx,g=rx,o=rx "${DUPLICACY_CLI_PATH}"
				echo "Updated to ${SELECTED_VERSION}"
			else
				echo "Could not download ${DOWNLOAD_URL}"
				rm -f "${DUPLICACY_CLI_PATH}"
				return 1
			fi
		fi 	
		;;
	esac

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
	    <key>KeepAlive</key>
	    <false/>
	
	    <key>Label</key>
	    <string>${LAUNCHD_BACKUP_NAME}</string>
	
	    <key>Program</key>
	    <string>${HELPER_APP_DIR}/${HELPER_BACKUP_APP_NAME}/Contents/MacOS/${HELPER_BACKUP_APP_NAME%.*}</string>
	
	${LAUNCHD_BACKUP_SCHEDULE}
	
	</dict>
	</plist>
	EOF
	return 0
}

function prepare_launchd_prune_plist()
{
	echo "Writing out ${LAUNCHD_PRUNE_PLIST}"
	mkdir -p ${LOGS_PATH}

	cat > "${LAUNCHD_PRUNE_PLIST}" <<- EOF
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
	    <key>KeepAlive</key>
	    <false/>
	
	    <key>Label</key>
	    <string>${LAUNCHD_PRUNE_NAME}</string>
	
	    <key>Program</key>
	    <string>${DUPLICACY_CONFIG_ROOT}/prune.sh</string>
	
	${LAUNCHD_PRUNE_SCHEDULE}
	
	</dict>
	</plist>
	EOF
	return 0
}
 
## Write out throttler scripts
#
function prepare_duplicacy_scripting()
{
	# Prune
	PRUNE="${DUPLICACY_CONFIG_ROOT}/prune.sh"
	echo "Writing out ${PRUNE}"

	cat > "${PRUNE}" <<- EOF
	#!/bin/bash
	DUPLICACY_CLI_PATH="${DUPLICACY_CLI_PATH}"
	DUPLICACY_GLOBAL_OPTIONS="${DUPLICACY_GLOBAL_OPTIONS}"
	DUPLICACY_PRUNE_OPTIONS="${DUPLICACY_PRUNE_OPTIONS}"
	LOGS_PATH="${LOGS_PATH}"
	DUPLICACY_CONFIG_ROOT="${DUPLICACY_CONFIG_ROOT}"
	EOF

	cat >> "${PRUNE}" <<- 'EOF'
	
	function terminator() {
	    [ ! -z "$duplicacy" ] && kill -TERM "${duplicacy}" 
	    duplicacy=
	}
	
	trap terminator SIGHUP SIGINT SIGQUIT SIGTERM EXIT
	
	mkdir -p ${LOGS_PATH}
	
	LOGFILE="${LOGS_PATH}/prune-$(date '+%Y-%m-%d-%H-%M-%S')"
	{
	    cd "${DUPLICACY_CONFIG_ROOT}"
	    "${DUPLICACY_CLI_PATH}" ${DUPLICACY_GLOBAL_OPTIONS} prune ${DUPLICACY_PRUNE_OPTIONS} &
	    duplicacy=$!
	
	    wait ${duplicacy}
	    duplicacy=
	} > >(tee "${LOGFILE}.log") 2> >(tee "${LOGFILE}.err")

	
	EOF

	chmod +x "${PRUNE}"|| exit $?


	# Throttled Backup
	BACKUP="${DUPLICACY_CONFIG_ROOT}/backup.sh"
	echo "Writing out ${BACKUP}"

	CPU_LIMITER_PATH="$(which cpulimit)"

	cat > "${BACKUP}" <<- EOF
	#!/bin/bash
	CPU_LIMIT_AC=${CPU_LIMIT_AC}
	CPU_LIMIT_BATTERY=${CPU_LIMIT_BATTERY}
	CPU_LIMITER_PATH="${CPU_LIMITER_PATH}"
	DUPLICACY_NAME="$(basename "${DUPLICACY_CLI_PATH}")"
	DUPLICACY_GLOBAL_OPTIONS="${DUPLICACY_GLOBAL_OPTIONS}"
	DUPLICACY_BACKUP_OPTIONS="${DUPLICACY_BACKUP_OPTIONS}"
	CHECK_POWER_SOURCE_EVERY="${CHECK_POWER_SOURCE_EVERY}"
	LOGS_PATH="${LOGS_PATH}"
	DUPLICACY_CONFIG_ROOT="${DUPLICACY_CONFIG_ROOT}"
	EOF

	cat >> "${BACKUP}" <<- 'EOF'
	
	SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
	DUPLICACY_CLI_PATH="${SCRIPTPATH}/${DUPLICACY_NAME}"

	function terminator() {
			echo termination signal received

	    [ ! -z "$duplicacy" ] && kill -TERM "${duplicacy}" 
	    duplicacy=
	    [ ! -z "$monitor" ] && kill -TERM "${monitor}"
	    monitor=
	}
	
	trap terminator SIGHUP SIGINT SIGQUIT SIGTERM EXIT
	
	function calculate_target_cpulimit(){
	    local cpulimit=${CPU_LIMIT_BATTERY};
	    case "$(pmset -g batt | grep 'Now drawing from')" in
	        *Battery*) cpulimit=${CPU_LIMIT_BATTERY} ;;
	        *)		   cpulimit=${CPU_LIMIT_AC} ;;
	    esac
	    echo $cpulimit
	}
	
	function monitor_and_adjust_priority()
	{
	    while [ ! -z "$(ps -p $duplicacy -o pid=)" ] ; do 
	        local new_limit=$(calculate_target_cpulimit)
	        if [[ "$last_limit" != "$new_limit" ]] ; then
	            echo "Setting new cpu limit $new_limit"
	            
	            "${CPU_LIMITER_PATH}" --limit=${new_limit} --include-children --pid=${duplicacy} &
	            
	            new_throttler=$!
	            [ ! -z "$throttler" ] && kill -TERM ${throttler}
	            throttler=${new_throttler}
	            last_limit=$new_limit
	        fi
	        sleep "${CHECK_POWER_SOURCE_EVERY}" 
	    done
	}
	
	mkdir -p ${LOGS_PATH}
	
	LOGFILE="${LOGS_PATH}/backup-$(date '+%Y-%m-%d-%H-%M-%S')"
	{
		echo "Running in ${DUPLICACY_CONFIG_ROOT} as $(id -un):$(id -gn)"
	    cd "${DUPLICACY_CONFIG_ROOT}"
	    "${DUPLICACY_CLI_PATH}" ${DUPLICACY_GLOBAL_OPTIONS} backup ${DUPLICACY_BACKUP_OPTIONS} &
	    duplicacy=$!
	
	    monitor_and_adjust_priority &
	    monitor=$!
	
	    wait ${duplicacy}
	    duplicacy=
	} > >(tee "${LOGFILE}.log") 2> >(tee "${LOGFILE}.err")
	
	EOF

	chmod +x "${BACKUP}"|| exit $?
	return 0;
}

function prepare_platypus_wrapper()
{
	HELPER_APP_DIR="${DUPLICACY_CONFIG_ROOT}"
	echo "Preparing app wrapper"
	mkdir -p "${HELPER_APP_DIR}"
	
	platypus --overwrite \
		--name "${HELPER_BACKUP_APP_NAME%.*}" \
		--interface-type 'None' \
		--quit-after-execution \
		--background \
		--bundled-file  "${DUPLICACY_CLI_PATH}" \
		--bundle-identifier ${LAUNCHD_BACKUP_NAME} \
		"${DUPLICACY_CONFIG_ROOT}/backup.sh" \
		"${HELPER_APP_DIR}/${HELPER_BACKUP_APP_NAME}" || exit $?
		
	echo "Please add \"${HELPER_APP_DIR}/${HELPER_BACKUP_APP_NAME}\" to Full Disk Access in System Preferences. Remove existing one if present."	
	open "${HELPER_APP_DIR}"
}

if [[ $(id -u) != 0 ]]; then
	sudo -p 'Restarting as root, password: ' bash "$0" "$@"
	exit $?
fi

if [ ! -f "${DUPLICACY_CONFIG_ROOT}/.duplicacy/preferences" ] ; then 
	echo "Please initialize duplicacy in ${DUPLICACY_CONFIG_ROOT} pointing to correct repository first. See -repository flag."
	exit 2; 
fi 

echo "Excluding the cache folder from time machine backups"
tmutil addexclusion "${DUPLICACY_CONFIG_ROOT}/.duplicacy/cache"

echo "Stopping and unloading existing daemons"
launchctl stop "${LAUNCHD_BACKUP_NAME}" 2>/dev/null
launchctl unload "${LAUNCHD_BACKUP_PLIST}" 2>/dev/null

launchctl stop "${LAUNCHD_PRUNE_NAME}" 2>/dev/null
launchctl unload "${LAUNCHD_PRUNE_PLIST}" 2>/dev/null


update_duplicacy_binary || exit $?
prepare_duplicacy_scripting || exit $?
prepare_platypus_wrapper || exit $?

prepare_launchd_backup_plist || exit $?
prepare_launchd_prune_plist || exit $?


echo "Loading the daemon \"${LAUNCHD_BACKUP_NAME}\""
launchctl load -w "${LAUNCHD_BACKUP_PLIST}" || exit $?

echo "Loading the daemon \"${LAUNCHD_PRUNE_NAME}\""
launchctl load -w "${LAUNCHD_PRUNE_PLIST}" || exit $?

echo "To manually start or stop the backup run"
echo "sudo launchctl start \"${LAUNCHD_BACKUP_NAME}\""
echo "sudo launchctl stop \"${LAUNCHD_BACKUP_NAME}\""


echo "Success."
