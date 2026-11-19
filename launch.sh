#!/bin/sh
# Syncthing.pak for NX Redux.
#
# Same three settings as the MinUI pak (Enabled, Start on boot, Syncthing
# version), shown with NX Redux's native options.elf instead of minui-list.
# options.elf edits an INI file from a JSON schema and exits on B; this script
# writes the INI from the real state, lets the user edit it, then applies
# whatever changed and shows the menu again until nothing changes.
#
# NX Redux exports SDCARD_PATH, LOGS_PATH and DEVICE but not PLATFORM or
# USERDATA_PATH, so those are derived here.
PAK_DIR="$(cd "$(dirname "$0")" && pwd)"
PAK_NAME="$(basename "$PAK_DIR")"
PAK_NAME="${PAK_NAME%.*}"

export SDCARD_PATH="${SDCARD_PATH:-/mnt/SDCARD}"
export PLATFORM="${PLATFORM:-tg5040}"
export USERDATA_PATH="${USERDATA_PATH:-$SDCARD_PATH/.userdata/$PLATFORM}"
export LOGS_PATH="${LOGS_PATH:-$USERDATA_PATH/logs}"
export HOME="$USERDATA_PATH/$PAK_NAME"

mkdir -p "$LOGS_PATH" "$HOME"
rm -f "$LOGS_PATH/$PAK_NAME.txt"
exec >>"$LOGS_PATH/$PAK_NAME.txt" 2>&1
set -x

cd "$PAK_DIR" || exit 1

architecture=arm
if uname -m | grep -q '64'; then
    architecture=arm64
fi
export LD_LIBRARY_PATH="$PAK_DIR/lib:$LD_LIBRARY_PATH"
export PATH="$PAK_DIR/bin/$architecture:$PAK_DIR/bin:$SYSTEM_PATH/bin:$PATH"

SERVICE_NAME="syncthing"
NETWORK_PORT=8384
AUTO_SH="$USERDATA_PATH/auto.sh"
SCHEMA="/tmp/$PAK_NAME-options.json"
INI="/tmp/$PAK_NAME-options.ini"

# shellcheck source=bin/syncthing-version.sh
. "$PAK_DIR/bin/syncthing-version.sh"

chmod +x "$PAK_DIR"/bin/service-* "$PAK_DIR/bin/on-boot" \
    "$PAK_DIR/bin/$architecture/syncthing" "$PAK_DIR/bin/v1/$architecture/syncthing" 2>/dev/null

if ! command -v options.elf >/dev/null 2>&1; then
    echo "options.elf not found: is this NX Redux?" >&2
    exit 1
fi

service_running() {
    "$PAK_DIR/bin/service-is-running"
}

will_start_on_boot() {
    grep -q "$PAK_NAME.pak-on-boot" "$AUTO_SH" >/dev/null 2>&1
}

enable_start_on_boot() {
    if [ ! -f "$AUTO_SH" ]; then
        printf '#!/bin/sh\n\n' >"$AUTO_SH"
    fi
    disable_start_on_boot
    echo "test -f \"$PAK_DIR/bin/on-boot\" && \"$PAK_DIR/bin/on-boot\" # $PAK_NAME.pak-on-boot" >>"$AUTO_SH"
    chmod +x "$AUTO_SH"
    sync
}

disable_start_on_boot() {
    [ -f "$AUTO_SH" ] && sed -i "/$PAK_NAME.pak-on-boot/d" "$AUTO_SH"
    sync
    return 0
}

get_address() {
    if [ "$(cat /sys/class/net/wlan0/operstate 2>/dev/null)" != "up" ]; then
        echo "not connected to WiFi"
        return
    fi
    ip="$(ip addr show wlan0 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)"
    if [ -z "$ip" ]; then
        echo "not connected to WiFi"
        return
    fi
    echo "http://$ip:$NETWORK_PORT"
}

wait_for() {
    # wait_for running|stopped
    want="$1"
    i=0
    while [ "$i" -lt 15 ]; do
        if service_running; then
            [ "$want" = "running" ] && return 0
        else
            [ "$want" = "stopped" ] && return 0
        fi
        i=$((i + 1))
        sleep 1
    done
    return 1
}

bool_word() {
    if "$@"; then echo on; else echo off; fi
}

# Writes the INI options.elf edits, from the real state of the device.
write_ini() {
    {
        echo "[syncthing]"
        echo "enabled=$(bool_word service_running)"
        echo "boot=$(bool_word will_start_on_boot)"
        echo "version=$(syncthing_selected_version)"
    } >"$INI"
}

# The hint line is the only place options.elf shows free text, so it carries
# the status that the MinUI pak showed as PID / Address rows, plus the result
# of the last action.
write_schema() {
    status="Syncthing is stopped."
    if service_running; then
        status="Running: $(get_address) (PID $(pgrep "$SERVICE_NAME" | head -n 1))"
    fi
    [ -n "$LAST_RESULT" ] && status="$LAST_RESULT  $status"

    cat >"$SCHEMA" <<EOF
{
  "emulator": "Syncthing",
  "options_hint": "$status",
  "sections": [{
    "name": "Settings",
    "ini_section": "syncthing",
    "items": [{
      "key": "enabled",
      "label": "Enabled",
      "description": "Run the Syncthing service. Web UI on port $NETWORK_PORT.",
      "type": "enum",
      "values": ["off", "on"],
      "labels": ["Off", "On"],
      "default": "off"
    }, {
      "key": "boot",
      "label": "Start on boot",
      "description": "Start Syncthing automatically when the device boots.",
      "type": "enum",
      "values": ["off", "on"],
      "labels": ["Off", "On"],
      "default": "off"
    }, {
      "key": "version",
      "label": "Syncthing version",
      "description": "1.x keeps its index in LevelDB and works on FAT cards; it is no longer updated. 2.x is current. Switching rebuilds the index.",
      "type": "enum",
      "values": ["2", "1"],
      "labels": ["2.x", "1.x"],
      "default": "2"
    }]
  }]
}
EOF
}

ini_get() {
    sed -n "s/^$1[ \t]*=[ \t]*//p" "$INI" | tr -d '\r' | head -n 1
}

start_service() {
    "$PAK_DIR/bin/service-on" && wait_for running
}

stop_service() {
    "$PAK_DIR/bin/service-off"
    wait_for stopped
}

# Applies the difference between the state before the menu and the INI after.
# Prints the result for the hint line; returns 1 when nothing changed.
apply_changes() {
    old_enabled="$1"
    old_boot="$2"
    old_version="$3"
    enabled="$(ini_get enabled)"
    boot="$(ini_get boot)"
    version="$(ini_get version)"
    changed=1
    LAST_RESULT=""

    if [ "$old_version" != "$version" ] && [ -n "$version" ]; then
        changed=0
        syncthing_set_version "$version"
        # Each version builds its own index, so restart what is running now.
        if service_running; then
            stop_service
            if start_service; then
                LAST_RESULT="Switched to ${version}.x."
            else
                LAST_RESULT="Could not start Syncthing ${version}.x (see logs)."
            fi
        else
            LAST_RESULT="Using ${version}.x."
        fi
    fi

    if [ "$old_enabled" != "$enabled" ] && [ -n "$enabled" ]; then
        changed=0
        if [ "$enabled" = "on" ]; then
            if service_running || start_service; then
                LAST_RESULT="Started."
            else
                LAST_RESULT="Could not start Syncthing (see logs)."
            fi
        else
            if stop_service; then
                LAST_RESULT="Stopped."
            else
                LAST_RESULT="Could not stop Syncthing."
            fi
        fi
    fi

    if [ "$old_boot" != "$boot" ] && [ -n "$boot" ]; then
        changed=0
        if [ "$boot" = "on" ]; then
            enable_start_on_boot && LAST_RESULT="$LAST_RESULT Starts on boot."
        else
            disable_start_on_boot && LAST_RESULT="$LAST_RESULT Won't start on boot."
        fi
    fi

    return $changed
}

cleanup() {
    rm -f "$SCHEMA" "$INI"
}

main() {
    trap cleanup EXIT INT TERM HUP QUIT
    LAST_RESULT=""

    while true; do
        write_ini
        write_schema
        old_enabled="$(ini_get enabled)"
        old_boot="$(ini_get boot)"
        old_version="$(ini_get version)"

        options.elf --json "$SCHEMA" --ini "$INI" --game "Syncthing" 2>>"$LOGS_PATH/$PAK_NAME.options.txt"

        apply_changes "$old_enabled" "$old_boot" "$old_version" || break
    done
}

main "$@"
