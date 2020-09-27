#!/bin/bash

### Setup
#

DUPLICACY_CONFIG_DIR=/Users/.duplicacy
TARGET_EXECUTABLE=/usr/local/bin/duplicacy

function check_utilities()
{
    local error_code=0
    
    for cmd in wget jq curl
    do
       if ! command -v $cmd > /dev/null ; then error_code=1; printf "Missing %s\n" "$cmd"; fi
    done 

    return $error_code
}

function update_duplicacy_binary()
{
    AVAILABLE_STABLE_VERSION=$(curl -s 'https://duplicacy.com/latest_cli_version' |jq -r '.stable' 2>/dev/null)

    LOCAL_EXECUTABLE_NAME="${DUPLICACY_CONFIG_DIR}/duplicacy_osx_x64_${AVAILABLE_STABLE_VERSION}"

    if [ -f "${LOCAL_EXECUTABLE_NAME}" ] 
    then
       echo "Version ${AVAILABLE_STABLE_VERSION} is up to date"
    else
        DOWNLOAD_URL="https://github.com/gilbertchen/duplicacy/releases/download/v${AVAILABLE_STABLE_VERSION}/duplicacy_osx_x64_${AVAILABLE_STABLE_VERSION}"
        if wget -O "${LOCAL_EXECUTABLE_NAME}" "${DOWNLOAD_URL}" ; then 
            chmod +x "${LOCAL_EXECUTABLE_NAME}"
            rm -f "${TARGET_EXECUTABLE}"
            ln -s "${LOCAL_EXECUTABLE_NAME}" "${TARGET_EXECUTABLE}"
            echo "Updated to ${AVAILABLE_STABLE_VERSION}"
        else
            echo "Could not download ${DOWNLOAD_URL}"
            rm -f "${LOCAL_EXECUTABLE_NAME}"
        return 1
        fi
    fi 
    return 0
}

check_utilities || exit 1

if [[ $(id -u) != 0 ]]; then
    sudo -p 'Restarting as root, password: ' bash $0 "$@"
    exit $?
fi

update_duplicacy_binary || exit 2
