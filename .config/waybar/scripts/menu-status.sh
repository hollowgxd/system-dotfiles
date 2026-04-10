#!/usr/bin/env bash

if pgrep -x wofi >/dev/null 2>&1; then
  printf '{"text":" ","class":"active","tooltip":"Applications menu is open"}\n'
else
  printf '{"text":" ","class":"inactive","tooltip":"Open applications menu"}\n'
fi
