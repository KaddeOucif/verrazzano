#!/usr/bin/env bash
#
# Copyright (c) 2020, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
#
SCRIPT_DIR=$(cd $(dirname "$0"); pwd -P)
. $SCRIPT_DIR/logging.sh

DEFAULT_CONFIG_FILE="$SCRIPT_DIR/config/config_defaults.json"

# Read a JSON installation config file and output the JSON to stdout
function read_config() {
  local config_file=$1
  local config_json=$(cat $config_file)
  echo "$config_json"
}

# get_config_value outputs to stdout a configuration value, without the surrounding quotes
# Note: if the value requested is an array, it will return a JSON array - use get_config_array
# if you want a bash array.
function get_config_value() {
  set -o pipefail
  local jq_expr="$1"
  local config_val=$(echo "$CONFIG_JSON" | jq -r "$jq_expr")
  if [ $? -ne 0 ] || [ -z "$config_val" ] || [ "$config_val" == "null" ]; then
    config_val=$(echo "$DEFAULT_CONFIG_JSON" | jq -r "$jq_expr")
  fi
  if [ $? -ne 0 ]; then
    log "Error reading $jq_expr from config files"
    return 1
  fi
  if [ "$config_val" == "null" ]; then
    config_val=""
  fi
  echo $config_val
}

# get_config_array outputs to stdout, the contents of a configuration array element. It expects
# input expression to be in the form of ".someField.someArray[]" i.e. with trailing box brackets. Caller should enclose return
# value in parentheses to get the result as an array
# (e.g.) MY_CONFIG_ARRAY=($(get_config_array ".ingress.nginx.extraInstallArgs[]"))
# Array elements will each be enclosed in quotes
function get_config_array() {
  set -o pipefail
  local jq_expr="$1"
  local config_array=($(echo $CONFIG_JSON | jq -c $jq_expr | tr "\n" " "))
  if [ $? -ne 0 ] || [ -z "$config_array" ]; then
    config_array=($(echo $DEFAULT_CONFIG_JSON | jq -c $jq_expr | tr "\n" " "))
  fi
  if [ $? -ne 0 ]; then
    log "Error reading $jq_expr from config files"
    return 1
  fi
  echo "${config_array[@]}"
}

log "Reading default installation config file $DEFAULT_CONFIG_FILE"
DEFAULT_CONFIG_JSON="$(read_config $DEFAULT_CONFIG_FILE)"

if [ -z "$INSTALL_CONFIG_FILE" ]; then
  INSTALL_CONFIG_FILE=$DEFAULT_CONFIG_FILE
  CONFIG_JSON=$DEFAULT_CONFIG_JSON
else
  log "Reading installation config file $INSTALL_CONFIG_FILE"
  CONFIG_JSON="$(read_config $INSTALL_CONFIG_FILE)"
fi

## Test cases - TODO remove before merging
#ENV_NAME=$(get_config_value ".environmentName")
#log "got environmentName value ${ENV_NAME}"
#EXTRA_ARG0=$(get_config_value ".ingress.verrazzano.extraInstallArgs[0]")
#log "status $? and got 0th extra argument value ${EXTRA_ARG0}"
#EXTRA_ARGS_ARR=($(get_config_array ".ingress.verrazzano.extraInstallArgs[]"))
#echo "status $? and got array [ ${EXTRA_ARGS_ARR[@]} ] containing ${EXTRA_ARGS_ARR[0]} and ${EXTRA_ARGS_ARR[1]}"