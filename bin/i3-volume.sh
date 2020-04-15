#!/bin/bash

# modified from https://github.com/hastinbe/i3-volume

get_default_sink() {
  SINKS=$(pacmd list-sinks)
  DEFAULT_SINK_INDEX=$(echo "$SINKS" | grep "* index:" | awk '{print $3}')
  DEFAULT_SINK_DESCRIPTION=$(echo "$SINKS" |
        awk -W posix '/^[ \t\*]+index: /{insink = $3 == "'$DEFAULT_SINK_INDEX'"}
          /^[ \t]+device.description / && insink {gsub("\"", ""); print $3; exit}')
  SOURCES=$(pacmd list-sources)
  DEFAULT_SOURCE_INDEX=$(echo "$SOURCES" | grep "* index:" | awk '{print $3}')
  DEFAULT_SOURCE_DESCRIPTION=$(echo "$SOURCES" |
        awk -W posix '/^[ \t\*]+index: /{insink = $3 == "'$DEFAULT_SOURCE_INDEX'"}
          /^[ \t]+device.description / && insink {gsub("\"", ""); print $3; exit}')
}

get_volume() {
    pacmd list-sinks |
        awk -W posix '/^[ \t\*]+index: /{insink = $3 == "'$DEFAULT_SINK_INDEX'"}
                      /^[ \t]+volume: / && insink {gsub("%", ""); print $5; exit}'
}

get_mic_volume() {
    pacmd list-sources |
        awk -W posix '/^[ \t\*]+index: /{insink = $3 == "'$DEFAULT_SOURCE_INDEX'"}
                      /^[ \t]+volume: / && insink {gsub("%", ""); print $5; exit}'
}

raise_volume() {
    local step="${1:-5}"
    set_volume "+${step}%"
}


lower_volume() {
    local step="${1:-5}"
    set_volume "-${step}%"
}

set_volume() {
    pactl set-sink-volume "$DEFAULT_SINK_INDEX" "$1"
}

toggle_mute() {
    pactl set-sink-mute "$DEFAULT_SINK_INDEX" toggle
}

is_muted() {
    muted=$(pacmd list-sinks |
                   awk -W posix '/^[ \t\*]+index: /{insink = $3 == "'$DEFAULT_SINK_INDEX'"}
                                 /^[ \t]+muted: / && insink {print $2; exit}')
    [ "$muted" = "yes" ]
}

is_mic_muted() {
    muted=$(pacmd list-sources |
                   awk -W posix '/^[ \t\*]+index: /{insink = $3 == "'$DEFAULT_SOURCE_INDEX'"}
                                 /^[ \t]+muted: / && insink {print $2; exit}')
    [ "$muted" = "yes" ]
}

get_volume_icon() {
    local vol="$1"
    local icon

    if [ "$vol" -ge 70 ]; then icon="audio-volume-high"
    elif [ "$vol" -ge 40 ]; then icon="audio-volume-medium"
    elif [ "$vol" -gt 0 ]; then icon="audio-volume-low"
    else icon="audio-volume-low"
    fi

    echo "${icon}"
}

# Display a notification indicating the volume is muted.
notify_muted() {
    if $opt_use_dunstify; then
        dunstify -i audio-volume-muted -t $expires -h int:value:0 -h string:synchronous:volume "Volume muted" -r 1000
    else
        notify-send -i audio-volume-muted -t $expires -h int:value:0 -h string:synchronous:volume "Volume muted"
    fi
}

# Display a notification indicating the current volume.
notify_volume() {
    local vol=$(get_volume)
    local icon=$(get_volume_icon "$vol")
    local text="Volume ${vol}%"

    if $opt_show_volume_progress; then
        local progress=$(get_progress_bar "$vol")
        text="$text $progress"
    fi

    if $opt_use_dunstify; then
        dunstify -i "$icon" -t $expires -h int:value:"$vol" -h string:synchronous:volume "$text" -r 1000
    else
        notify-send -i "$icon" -t $expires -h int:value:"$vol" -h string:synchronous:volume "$text"
    fi
}

update_statusline() {
    local signal="$1"
    local proc="$2"
    pkill "-$signal" "$proc"
}

get_progress_bar() {
    local percent="$1"
    local max_percent=${2:-100}
    local divisor=${3:-5}
    local progress=$((($percent > $max_percent ? $max_percent : $percent) / $divisor))

    printf '█%.0s' $(eval echo "{1..$progress}")
}

usage() {
    echo "Usage: $0 [options]
Control volume and related notifications.

Options:
  -d <amount>       decrease volume
  -e <expires>      expiration time of notifications, in milliseconds
  -i <amount>       increase volume
  -m                toggle mute
  -n                show notifications
  -p                show text volume progress bar
  -s <sink_name>    symbolic name of sink (pulseaudio only)
  -t <process_name> name of status line process. must be used with -u
  -u <signal>       update status line using signal. must be used with -t
  -v <value>        set volume
  -y                use dunstify instead of notify-send
  -h                display this help and exit
" 1>&2
    exit 1
}
###########################################################

opt_decrease_volume=false
opt_increase_volume=false
opt_mute_volume=false
opt_notification=false
opt_set_volume=false
opt_show_volume_progress=false
opt_use_amixer=false
opt_use_dunstify=false
signal=""
sink=""
statusline=""
volume=5
expires="1500"
opt_get_volume=false

while getopts ":d:e:hi:mnps:t:u:v:yg" o; do
    case "$o" in
        d)
            opt_decrease_volume=true
            volume="${OPTARG}"
            ;;
        e)
            expires="${OPTARG}"
            ;;
        i)
            opt_increase_volume=true
            volume="${OPTARG}"
            ;;
        m)
            opt_mute_volume=true
            ;;
        n)
            opt_notification=true
            ;;
        p)
            opt_show_volume_progress=true
            ;;
        s)
            sink="${OPTARG}"
            ;;
        t)
            statusline="${OPTARG}"
            ;;
        u)
            signal="${OPTARG}"
            ;;
        v)
            opt_set_volume=true
            volume="${OPTARG}"
            ;;
        y)
            opt_use_dunstify=true
            ;;
        g)
            opt_get_volume=true
            ;;
        h | *)
            usage
            ;;
    esac
done
shift $((OPTIND-1)) # Shift off options and optional --

if [[ "$sink" == "" ]]; then
  get_default_sink
fi


if ${opt_increase_volume}; then
    raise_volume $volume
fi

if ${opt_decrease_volume}; then
    lower_volume $volume
fi

if ${opt_set_volume}; then
    set_volume $volume
fi

if ${opt_mute_volume}; then
    toggle_mute
fi

# The options below this line must be last
if ${opt_notification}; then
    if is_muted; then
        notify_muted
    else
        notify_volume
    fi
fi

if ${opt_get_volume}; then
  if is_muted
  then
    vol="MUTED"
  else
    vol="$(get_volume)%"
  fi
  if is_mic_muted
  then
    mic_vol="MUTED"
  else
    mic_vol="$(get_mic_volume)%"
  fi
  echo "$DEFAULT_SINK_DESCRIPTION $vol $mic_vol"
fi

if [ -n "${signal}" ]; then
    if [ -z "${statusline}" ]; then
        usage
    fi
    update_statusline "${signal}" "${statusline}"
else
    if [ -n "${statusline}" ]; then
        usage
    fi
fi
