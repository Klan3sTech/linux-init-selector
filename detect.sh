#!/bin/sh
#
# detect.sh - Detect installed init systems on the host.
# This script is used only during installation by install.sh.
# It searches standard paths for supported init systems and outputs
# found entries in "name:path" format (space separated).
#
# Supported: systemd, OpenRC, runit, dinit, SysVinit, s6-linux-init,
# GNU Shepherd, Finit, sinit, Epoch, BusyBox init.
# POSIX compliant, uses only sh and standard utilities.
#

# Append name:path to $found if the executable exists and this init name
# has not been added yet.  The function deliberately keeps the first match,
# so candidate order is important.
add_found() {
    name=$1
    path=$2

    [ -n "$name" ] || return 1
    [ -x "$path" ] || return 1

    case " $found " in
        *" ${name}:"*) return 0 ;;
    esac

    if [ -z "$found" ]; then
        found="${name}:${path}"
    else
        found="${found} ${name}:${path}"
    fi
}

# Return true if a path is clearly a systemd init binary/symlink.
is_systemd_init() {
    path=$1

    case "$path" in
        */systemd/systemd) return 0 ;;
    esac

    if command -v readlink >/dev/null 2>&1; then
        target=$(readlink -f "$path" 2>/dev/null || readlink "$path" 2>/dev/null || true)
        case "$target" in
            *systemd*) return 0 ;;
        esac
    fi

    return 1
}

# Return true if a path is clearly a BusyBox init symlink.
is_busybox_init() {
    path=$1

    if command -v readlink >/dev/null 2>&1; then
        target=$(readlink -f "$path" 2>/dev/null || readlink "$path" 2>/dev/null || true)
        case "$target" in
            *busybox*|*BusyBox*) return 0 ;;
        esac
    fi

    return 1
}

# Function to detect init systems.
# Returns the first found executable path per name to avoid duplicates.
detect_inits() {
    found=""

    # Native init binaries.  Avoid generic /sbin/init here because it is often
    # a symlink to another init and needs special classification below. Prefer
    # runit's regular binary; Debian's runit-init is only a fallback because it
    # is supplied by an optional init-replacement package.
    candidates="
systemd:/usr/lib/systemd/systemd
systemd:/lib/systemd/systemd
openrc:/sbin/openrc-init
openrc:/usr/sbin/openrc-init
openrc:/usr/bin/openrc-init
runit:/sbin/runit
runit:/usr/sbin/runit
runit:/usr/bin/runit
runit:/usr/local/sbin/runit
runit:/lib/runit/runit
runit:/lib/runit/runit-init
runit:/sbin/runit-init
runit:/usr/sbin/runit-init
runit:/usr/bin/runit-init
runit:/usr/local/sbin/runit-init
dinit:/sbin/dinit
dinit:/usr/sbin/dinit
dinit:/usr/bin/dinit
dinit:/usr/local/sbin/dinit
dinit:/usr/local/bin/dinit
s6:/etc/s6-linux-init/current/bin/init
s6:/sbin/s6-linux-init
s6:/usr/sbin/s6-linux-init
s6:/usr/local/sbin/s6-linux-init
shepherd:/usr/bin/shepherd
shepherd:/bin/shepherd
shepherd:/usr/sbin/shepherd
shepherd:/usr/local/bin/shepherd
finit:/sbin/finit
finit:/usr/sbin/finit
finit:/usr/local/sbin/finit
sinit:/sbin/sinit
sinit:/usr/sbin/sinit
sinit:/usr/local/sbin/sinit
epoch:/sbin/epoch
epoch:/usr/sbin/epoch
epoch:/usr/local/sbin/epoch
"

    for pair in $candidates; do
        name=${pair%%:*}
        path=${pair#*:}
        add_found "$name" "$path"
    done

    # Classify generic /sbin/init-like paths carefully.  This prevents a
    # systemd host from being reported as SysVinit just because /sbin/init is
    # present.
    for init_path in /sbin/init /usr/sbin/init /bin/init; do
        [ -x "$init_path" ] || continue

        if is_systemd_init "$init_path"; then
            add_found systemd "$init_path"
            continue
        fi

        if is_busybox_init "$init_path"; then
            add_found busybox-init "$init_path"
            continue
        fi

        # SysVinit normally has /etc/inittab.  Require it to avoid mislabeling
        # arbitrary /sbin/init implementations.
        if [ -f /etc/inittab ]; then
            case "$init_path" in
                /sbin/init|/usr/sbin/init) add_found sysvinit "$init_path" ;;
            esac
        fi
    done

    echo "$found"
}

# If script is executed directly (not sourced), print detected inits.
if [ "${0##*/}" = "detect.sh" ]; then
    detect_inits
fi
