#!/usr/bin/env bash

set -u

BAT_DIR=""
for supply_dir in /sys/class/power_supply/*; do
  [[ -e "${supply_dir}" ]] || continue

  supply_type=""
  supply_present="1"

  [[ -r "${supply_dir}/type" ]] && supply_type="$(<"${supply_dir}/type")"
  [[ -r "${supply_dir}/present" ]] && supply_present="$(<"${supply_dir}/present")"

  if [[ "${supply_type}" == "Battery" && "${supply_present}" != "0" ]]; then
    BAT_DIR="${supply_dir}"
    break
  fi
done

if [[ -z "${BAT_DIR}" ]]; then
  printf '{"text":" ","tooltip":"No battery detected","class":"ac"}\n'
  exit 0
fi

capacity="0"
status="Unknown"

if [[ -r "${BAT_DIR}/capacity" ]]; then
  capacity="$(<"${BAT_DIR}/capacity")"
fi

if [[ -r "${BAT_DIR}/status" ]]; then
  status="$(<"${BAT_DIR}/status")"
fi

is_ac=0
for online_file in /sys/class/power_supply/*/online; do
  [[ -r "${online_file}" ]] || continue
  supply_name="$(basename "$(dirname "${online_file}")")"
  if [[ "${supply_name}" =~ ^(AC|ACAD|ADP|Mains) ]]; then
    online_val="$(<"${online_file}")"
    if [[ "${online_val}" == "1" ]]; then
      is_ac=1
      break
    fi
  fi
done

if [[ "${status}" == "Charging" || "${status}" == "Full" ]]; then
  is_ac=1
fi

class_name="level-1"
if [[ "${is_ac}" == "1" ]]; then
  class_name="ac"
elif (( capacity > 75 )); then
  class_name="level-4"
elif (( capacity > 50 )); then
  class_name="level-3"
elif (( capacity > 25 )); then
  class_name="level-2"
fi

tooltip_text="Battery: ${capacity}%\nStatus: ${status}"
if [[ "${class_name}" == "ac" ]]; then
  tooltip_text="Power: AC\nBattery: ${capacity}%\nStatus: ${status}"
fi

printf '{"text":" ","tooltip":"%s","class":"%s"}\n' "${tooltip_text}" "${class_name}"
