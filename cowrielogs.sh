#!/bin/bash

LOG_PATH="/home/cowrie/cowrie/var/log/cowrie/cowrie.log"
SHOW_COMMANDS_ONLY=false

# Handle argument
if [[ "$1" == "--commands-only" ]]; then
    SHOW_COMMANDS_ONLY=true
fi

# Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

echo -e "${CYAN}[*] Parsing and summarizing Cowrie sessions...${NC}"
if $SHOW_COMMANDS_ONLY; then
    echo -e "${YELLOW}[*] Showing only sessions where commands were executed.${NC}"
fi

# Parse log and store sessions
grep -E 'HoneyPotSSHTransport|login attempt|CMD:|Connection lost after' "$LOG_PATH" | awk -v showOnly="$SHOW_COMMANDS_ONLY" -v RED="$RED" -v GREEN="$GREEN" -v YELLOW="$YELLOW" -v BLUE="$BLUE" -v CYAN="$CYAN" -v NC="$NC" '
{
    if ($0 ~ /HoneyPotSSHTransport,[0-9]+,[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) {
        match($0, /HoneyPotSSHTransport,[0-9]+,[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/, arr)
        split(arr[0], parts, ",")
        session_id = parts[2]
        ip = parts[3]
        sessions[session_id]["ip"] = ip
    }
    if ($0 ~ /login attempt \[/) {
        match($0, /login attempt \[b.([^\/]*)\/b.([^]]*)/, creds)
        user = creds[1]
        pass = creds[2]
        sessions[session_id]["login"] = user "/" pass
        sessions[session_id]["start"] = substr($1, 1, 19)
    }
    if ($0 ~ /CMD:/) {
        cmd = substr($0, index($0, "CMD:") + 5)
        sessions[session_id]["cmds"] = sessions[session_id]["cmds"] cmd "\n"
    }
    if ($0 ~ /Connection lost after/) {
        match($0, /after ([0-9.]+) seconds/, t)
        sessions[session_id]["duration"] = t[1]
    }
}
END {
    for (id in sessions) {
        cmds = sessions[id]["cmds"]
        if (showOnly == "true" && length(cmds) == 0) {
            continue
        }

        print "\n" BLUE "------------------------ SESSION " id " ------------------------" NC
        print YELLOW "IP Address:  " NC sessions[id]["ip"]
        print YELLOW "Login:      " NC sessions[id]["login"]
        print YELLOW "Start Time: " NC sessions[id]["start"]
        print YELLOW "Duration:   " NC sessions[id]["duration"] " sec"
        print YELLOW "Commands:" NC

        if (length(cmds) > 0) {
            print GREEN cmds NC
        } else {
            print RED " No commands executed. " NC
        }
    }
}'
