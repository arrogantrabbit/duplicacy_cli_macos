This is a handy script to download and install duplicacy_cli to run under launchd and backup all users, without the need to disable SIP

## The problem

Duplicacy CLI on macOS used to not be able to access sensitive user folders such as Documents and Pictures when ran standalone. It dis not seem to be possible to grant full disk access to a naked executable that is not an app bundle. When launched via Duplicacy GUI that problem did not exist as the CLI engines inherits permissions granted to the parent app bundle. 

This problem no longer exists, however using Duplicacy GUI is still undesirable for several reasons:

- It's impossible to control CPU utilization of the CLI engine (without jumping through hoops)
- Running closed source app that fetches executables from the internet under account that needs access to all users data is sub-optimal.
- macOS already has a perfectly good scheduler. 

## The solution

We will write a script to accomplish the following tasks:

- Fetch the specified version of duplicacy from the web or local build directly. Support specific version number, specific local path, and "Latest" and "Stable" channels.
- Create aux script to launch and throttle duplicacy_cli depending on power status of your mac -- support separate limits on battery vs on wall power. (cpulimit)
- Prompt to give the duplicacy executable full disk access
- Configure launchd daemon to run the backup and prune with configurable retention policy

## Prerequisities

We will assume that the following is true:
- Duplicacy is configured under `/Library/Duplicacy` to backup `/Users`. This boils down to doing something along these lines when initializing the repository:
    ```bash
    sudo mkdir -p /Library/Duplicacy
    cd /Library/Duplicacy
    sudo duplicacy init -repository /Users <snapshot id> <storage url>
    ```
- [homebrew](https://brew.sh) is installed. Depending on the configuration we would need one or few of the following utilities: `cpulimit`, `wget`, `jq`, `curl`. The script will prompt for the missing ones, which then could be installed with
    ```bash
    brew install cpulimit wget jq curl
    ```

## To run

Clone the repository https://github.com/arrogantrabbit/duplicacy_cli_macos, review the `install.sh` file; make changes as needed to the schedule and/or duplicacy version and run.

It's also possible to override the environment variables without editing the file. For example, do use a specific version of duplicacy one might run: 

    REQUESTED_CLI_VERSION=3.2.4 ./install.sh

The script will open Finder and highlight an executable to be dragged to the `Full Disk Access` section in the Security & Privacy.
