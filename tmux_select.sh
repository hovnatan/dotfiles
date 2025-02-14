#!/usr/bin/env bash

sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null)
if [ -n "$sessions" ]; then
    echo "Available sessions:"
    echo "$sessions" | nl
    echo -n "Select session number (or press enter to skip): "
    read choice
    if [ -n "$choice" ]; then
        session=$(echo "$sessions" | sed -n "${choice}p")
        if [ -n "$session" ]; then
            tmux attach -t "$session"
            exit 0
        fi
        echo "Session not found"
    fi
    echo -n "Enter new session name (or press enter to continue with zsh): "
    read new_session
    if [ -n "$new_session" ]; then
        tmux new -s "$new_session"
        exit 0
    else
        exec zsh
    fi
else
    echo -n "No tmux sessions available. Enter new session name to create or press enter to continue with zsh: "
    read new_session
    if [ -n "$new_session" ]; then
        tmux new -s "$new_session"
        exit 0
    else
        exec zsh
    fi
fi