#!/bin/bash


LAYOUT=$(xkb-switch)

if [[ "$LAYOUT" != "us" ]]; then
  xkb-switch -s us
fi

rofimoji --skin-tone neutral

if [[ "$LAYOUT" != "us" ]]; then
  xkb-switch -s "$LAYOUT"
fi
