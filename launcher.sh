#!/bin/sh
# Name: @NAME@
# Author: kindle-fullscreen-browser
# Icon: @ICON@
# DontUseFBInk

# Opens a web page fullscreen in the Kindle's own browser (jailbroken Kindle; tested: 11th gen,
# FW 5.19.2). Tap this item in the library to start. Press the power button to leave.
# Template: deploy.ps1 fills in @NAME@, @URL@ and @ICON@. Edit the template, not the copy on the Kindle.
#
# How: the window manager reads layout tags from each window's title; the browser's says "PC:TS"
# (status bar + browser toolbar). xname.lua, run by KOReader's LuaJIT, changes that to "PC:N", and
# the window manager then gives the browser the whole screen. On exit the title is put back and the
# browser is closed. No files are changed.

# ---- settings ---------------------------------------------------------------
NAME="@NAME@"      # shown in messages and the log
URL="@URL@"        # the page to show
EXIT_ON_SLEEP=1    # 1 = power button returns to the library; 0 = page stays open after wake
# -----------------------------------------------------------------------------

HOME_DIR=/mnt/us/fullscreen-browser
XN_SRC=$HOME_DIR/xname.lua
USERLOG=$HOME_DIR/log.txt
LJ_SRC=/mnt/us/koreader/luajit
LJ=/tmp/fsbrowser-luajit
XN=/tmp/fsbrowser-xname.lua
PIDFILE=/tmp/fsbrowser.pid
SLEEPEV=/tmp/fsbrowser.sleep
KEEPLOG=/tmp/fsbrowser-keep.log
PENDING=/tmp/fsbrowser.pending
OUT=/tmp/fsbrowser.out
FBINK=/mnt/us/libkh/bin/fbink
BROWSER=com.lab126.browser
TAG_BARS=_PC:TS_
TAG_FULL=_PC:N_

# Stage 1: the library runs us from /mnt/us. Copy to /tmp under a fresh name (never overwrite a
# script that is running) and detach, so nothing keeps /mnt/us busy for USB drive mode.
if [ "$1" != "--detached" ]; then
    cd /
    RUN=/tmp/fsbrowser-run-$$.sh
    cp -f "$0" "$RUN" 2>/dev/null || RUN="$0"
    if command -v setsid >/dev/null 2>&1; then
        setsid sh "$RUN" --detached >/dev/null 2>&1 </dev/null &
    else
        nohup sh "$RUN" --detached >/dev/null 2>&1 </dev/null &
    fi
    exit 0
fi

cd /
case "$0" in /tmp/fsbrowser-run-*) rm -f "$0" ;; esac # the shell already has it open
if [ -s "$OUT" ]; then
    { echo "--- error output of the previous run:"; tail -n 20 "$OUT"; echo "---"; } >>"$PENDING"
fi
if [ -s "$KEEPLOG" ]; then # only left behind when the previous run did not clean up
    { echo "--- helper output of the previous run:"; tail -n 20 "$KEEPLOG"; echo "---"; } >>"$PENDING"
fi
exec >"$OUT" 2>&1
export DISPLAY="${DISPLAY:-:0}"

log() {
    # Lines collect in /tmp and move to /mnt/us when it is mounted (it is not in USB drive
    # mode). Open and close per line: never hold a file open on /mnt/us.
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$PENDING"
    if [ -d /mnt/us/documents ] && mkdir -p "$HOME_DIR" 2>/dev/null && cat "$PENDING" >>"$USERLOG" 2>/dev/null; then
        rm -f "$PENDING"
    fi
}
notify() { [ -x "$FBINK" ] && limit 5 "$FBINK" -q -pmM "$*"; }
active() { lipc-get-prop com.lab126.appmgrd activeApp 2>/dev/null; }
power_state() { lipc-get-prop com.lab126.powerd state 2>/dev/null; }
limit() { # limit SECONDS cmd... : run a command, kill it if it takes longer
    secs=$1; shift
    "$@" &
    cmd_pid=$!
    ( sleep "$secs"; kill "$cmd_pid" 2>/dev/null ) >/dev/null 2>&1 </dev/null &
    killer=$!
    wait "$cmd_pid"; rc=$?
    kill "$killer" 2>/dev/null
    return $rc
}
xname() { [ -x "$LJ" ] && [ -f "$XN" ] && limit 10 "$LJ" "$XN" "$@"; }
pids_of() { # pids whose cmdline matches $1
    for p in /proc/[0-9]*; do
        tr '\0' ' ' <"$p/cmdline" 2>/dev/null | grep -q -- "$1" && echo "${p#/proc/}"
    done
}

cleanup() {
    trap - INT TERM HUP
    log "stopping ($1)"
    [ -n "$KEEP_PID" ] && kill "$KEEP_PID" 2>/dev/null
    [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null
    [ "$(active)" = "$BROWSER" ] && lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
    sleep 2
    # Usual title back (so the browser has its bars if it is opened normally), then close it.
    xname set "$BROWSER" "$TAG_FULL" "$TAG_BARS" >/dev/null
    limit 5 lipc-set-prop com.lab126.appmgrd stop "app://$BROWSER"
    sleep 3
    for pid in $(pids_of "kindle_browser"); do kill "$pid" 2>/dev/null; done
    [ -f "$KEEPLOG" ] && log "fullscreen title set $(grep -c ' set ' "$KEEPLOG") time(s) (1 = it never reverted)"
    rm -f "$PIDFILE" "$SLEEPEV" "$KEEPLOG" "$LJ" "$XN"
    log "stopped (back in $(active))"
    exit 0
}

# One instance: a new start (of this or another page) replaces a running one, and waits for it
# to finish cleaning up.
if [ -f "$PIDFILE" ]; then
    OLD=$(cat "$PIDFILE")
    if [ -n "$OLD" ] && [ "$OLD" != "$$" ] && kill "$OLD" 2>/dev/null; then
        i=0
        while kill -0 "$OLD" 2>/dev/null && [ $i -lt 15 ]; do sleep 1; i=$((i + 1)); done
    fi
fi
echo $$ >"$PIDFILE"
trap 'cleanup signal' INT TERM HUP
# A helper left by a run that did not finish would hold its file and fight over the title.
for pid in $(pids_of "fsbrowser-xname.lua keep"); do kill "$pid" 2>/dev/null; done
rm -f "$LJ" "$XN"

# Keep the log short.
if [ -f "$USERLOG" ] && [ "$(wc -c <"$USERLOG")" -gt 65536 ]; then
    tail -n 200 "$USERLOG" >/tmp/fsbrowser-log.tmp && cat /tmp/fsbrowser-log.tmp >"$USERLOG"
    rm -f /tmp/fsbrowser-log.tmp
fi
log "starting $NAME: url=$URL fw=$(cat /etc/prettyversion.txt 2>/dev/null)"
# preventScreenSaver (set by other tools) also blocks the power button. Make sure it is off.
PREVENT=$(lipc-get-prop com.lab126.powerd preventScreenSaver 2>/dev/null)
if [ "$PREVENT" != "0" ]; then
    lipc-set-prop -i com.lab126.powerd preventScreenSaver 0
    log "preventScreenSaver was '$PREVENT', set to 0"
fi
sleep 2 # let the library's launcher finish first

# The fullscreen helper runs from /tmp, so it does not keep /mnt/us busy.
if [ -f "$LJ_SRC" ] && [ -f "$XN_SRC" ] && cp -f "$LJ_SRC" "$LJ" && cp -f "$XN_SRC" "$XN" && chmod 755 "$LJ"; then
    FULL=1
else
    FULL=0
    log "WARNING: $LJ_SRC or $XN_SRC missing - the page opens with the Kindle's top bars"
fi

# Wi-Fi on, and give it a moment to associate.
lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null
i=0
while [ $i -lt 20 ]; do
    WIFI=$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)
    [ "$WIFI" = "CONNECTED" ] && break
    sleep 1; i=$((i + 1))
done
log "wifi: ${WIFI:-unknown}"

# Wait up to ~30 s for the page: the browser shows a dead error page if it is not there yet.
i=0
until wget -q -T 4 -O /dev/null "$URL" 2>/dev/null; do
    i=$((i + 1))
    if [ $i -ge 6 ]; then
        log "cannot reach $URL"
        notify "$NAME: $URL is not reachable"
        rm -f "$PIDFILE" "$LJ" "$XN"
        exit 1
    fi
    [ $i -eq 1 ] && notify "$NAME: waiting for $URL ..."
    sleep 2
done
log "page reachable"

if [ "$FULL" = 1 ]; then
    # Retitle the browser window as soon as it appears, and again whenever the title reverts.
    # If this script dies, the helper notices and gives the browser its bars (and X) back.
    "$LJ" "$XN" keep "$BROWSER" "$TAG_BARS" "$TAG_FULL" 0 1 $$ >"$KEEPLOG" 2>&1 &
    KEEP_PID=$!
fi
lipc-set-prop com.lab126.appmgrd start "app://$BROWSER?view=$URL"

i=0
while [ $i -lt 30 ]; do
    [ "$(active)" = "$BROWSER" ] && break
    sleep 1; i=$((i + 1))
done
log "active app: $(active)"
if [ "$(active)" != "$BROWSER" ]; then
    log "browser did not come up"
    cleanup "browser-failed"
fi

# Power button: this exits (and its output appears) on the first goingToScreenSaver event.
if [ "$EXIT_ON_SLEEP" = "1" ]; then
    lipc-wait-event com.lab126.powerd goingToScreenSaver >"$SLEEPEV" 2>/dev/null &
    SLEEP_PID=$!
fi

GONE=0
LAST_STATE=
TICK=0
while :; do
    sleep 2
    [ -s "$SLEEPEV" ] && cleanup "power button: $(head -n 1 "$SLEEPEV")"
    STATE=$(power_state)
    [ "$STATE" != "$LAST_STATE" ] && log "power state: ${STATE:-unknown}"
    LAST_STATE=$STATE
    if [ "$EXIT_ON_SLEEP" = "1" ]; then
        case "$STATE" in *creen[Ss]aver*|*uspend*) cleanup "power button ($STATE)" ;; esac
    fi
    # Stay awake: restart the idle timer every 30 s (what KOReader does). Unlike preventScreenSaver,
    # this leaves the power button working.
    TICK=$((TICK + 1))
    if [ "$STATE" = "active" ] && [ $((TICK % 15)) -eq 1 ]; then
        lipc-set-prop -i com.lab126.powerd touchScreenSaverTimeout 1 || log "touchScreenSaverTimeout failed"
    fi
    # USB drive mode unmounts /mnt/us.
    grep -q ' /mnt/us ' /proc/mounts || cleanup "usb drive mode"
    # Something else took the screen while awake: stop quietly.
    APP=$(active)
    if [ "$STATE" = "active" ] && [ -n "$APP" ] && [ "$APP" != "$BROWSER" ]; then
        GONE=$((GONE + 1))
        [ "$GONE" -ge 2 ] && cleanup "left the browser ($APP)"
    else
        GONE=0
    fi
done
