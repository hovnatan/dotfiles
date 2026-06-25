#!/usr/bin/env bash

set -e

########################################################

( cd "$HOME" && npx skills add kunchenguid/lavish-axi --skill lavish -g )

########################################################

tmp=$(mktemp -d)
git clone --depth 1 https://github.com/coleam00/excalidraw-diagram-skill "$tmp"
rm -rf $HOME/.claude/skills/excalidraw-diagram
mkdir -p $HOME/.claude/skills
cp -r "$tmp" $HOME/.claude/skills/excalidraw-diagram
rm -rf "$tmp"

########################################################

( cd "$HOME" && npx skills@latest add mattpocock/skills -g )

########################################################

tmp=$(mktemp -d)
git clone --depth 1 https://github.com/mitsuhiko/agent-stuff "$tmp"
rm -rf $HOME/.claude/skills/tmux
mkdir -p $HOME/.claude/skills
cp -r "$tmp/skills/tmux" $HOME/.claude/skills/tmux
rm -rf "$tmp"
