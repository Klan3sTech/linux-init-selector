#!/bin/sh
#
# detect.sh - Detect installed init systems on the host.
# This script is used only during installation by install.sh.
# It searches standard paths for supported init systems and outputs
# found entries in "name:path" format (space separated).
# Supports: systemd, OpenRC, runit, dinit.
# POSIX compliant, uses only sh and standard utils.
#

# Function to detect init systems.
# Scans predefined candidate list of name:path pairs.
# Returns first found executable path per name to avoid duplicates.
detect_inits() {
    # Define candidates: name:absolute_path
    # Order matters: prefer specific binaries over generic /sbin/init
    # systemd paths first (common on most distros)
    candidates="
systemd:/usr/lib/systemd/systemd
systemd:/lib/systemd/systemd
systemd:/sbin/init
openrc:/sbin/openrc-init
openrc:/usr/sbin/openrc-init
runit:/sbin/runit-init
runit:/usr/sbin/runit-init
runit:/lib/runit/runit-init
dinit:/sbin/dinit
dinit:/usr/sbin/dinit
dinit:/usr/bin/dinit
"

    found=""
    # Split candidates by newline (POSIX way: use for with IFS)
    OLDIFS="$IFS"
    IFS='
'
    for line in $candidates; do
        [ -z "$line" ] && continue
        name=${line%%:*}
        path=${line#*:}
        # Check if executable and not already found for this name
        if [ -x "$path" ]; then
            case " $found " in
                *" ${name}:"*) continue ;;
            esac
            if [ -z "$found" ]; then
                found="${name}:${path}"
            else
                found="${found} ${name}:${path}"
            fi
        fi
    done
    IFS="$OLDIFS"

    echo "$found"
}

# If script is executed directly (not sourced), print detected inits
# This allows ./detect.sh to output list for install.sh
if [ "${0##*/}" = "detect.sh" ]; then
    detect_inits
fi
