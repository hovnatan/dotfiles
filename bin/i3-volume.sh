#!/bin/bash

# modified from https://github.com/hastinbe/i3-volume

get_default_sink_source() {
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

toggle_mute_mic() {
    pactl set-source-mute "$DEFAULT_SOURCE_INDEX" toggle
}

is_muted() {
    local muted=$(pacmd list-sinks |
                   awk -W posix '/^[ \t\*]+index: /{insink = $3 == "'$DEFAULT_SINK_INDEX'"}
                                 /^[ \t]+muted: / && insink {print $2; exit}')
    [ "$muted" = "yes" ]
}

is_mic_muted() {
    local muted=$(pacmd list-sources |
                   awk -W posix '/^[ \t\*]+index: /{insink = $3 == "'$DEFAULT_SOURCE_INDEX'"}
                                 /^[ \t]+muted: / && insink {print $2; exit}')
    [ "$muted" = "yes" ]
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
  -i <amount>       increase volume
  -m                toggle mute
  -n                show notifications
  -p                show text volume progress bar
  -y                use dunstify instead of notify-send
  -h                display this help and exit
" 1>&2
    exit 1
}
###########################################################

opt_decrease_volume=false
opt_increase_volume=false
opt_mute_volume=false
opt_mute_mic_volume=false
opt_notification=false
statusline=""
volume=5
expires="2000"
opt_get_volume=false

while getopts ":d:hi:mMnt:g" o; do
    case "$o" in
        d)
            opt_decrease_volume=true
            volume="${OPTARG}"
            ;;
        i)
            opt_increase_volume=true
            volume="${OPTARG}"
            ;;
        m)
            opt_mute_volume=true
            ;;
        M)
            opt_mute_mic_volume=true
            ;;
        n)
            opt_notification=true
            ;;
        t)
            statusline="${OPTARG}"
            ;;
        g)
            opt_get_volume=true
            ;;
        h | *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

get_default_sink_source

if ${opt_increase_volume}; then
    raise_volume $volume
fi

if ${opt_decrease_volume}; then
    lower_volume $volume
fi

if ${opt_mute_volume}; then
    toggle_mute
fi

if ${opt_mute_mic_volume}; then
    toggle_mute_mic
fi

if ${opt_notification}; then
    if is_muted
    then
      vol="MUTED"
    else
      vol="$(get_volume)"
      progress=$(get_progress_bar "$vol")
      vol="$vol% $progress"
    fi
    if is_mic_muted
    then
      mic_vol="MUTED"
    else
      mic_vol="$(get_mic_volume)"
      mic_vol="$mic_vol%"
    fi
    text="OUT:   $vol
IN:      $mic_vol"

    dunstify -i audio-volume-low -t $expires -r 1000 "Audio: $DEFAULT_SINK_DESCRIPTION" "$text"
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

pkill -RTMIN+10 i3blocks
