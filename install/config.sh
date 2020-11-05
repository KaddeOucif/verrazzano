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
  local config_array=($(echo $CONFIG_JSON | jq -rc $jq_expr | tr "\n" " "))
  if [ $? -ne 0 ] || [ -z "$config_array" ]; then
    config_array=($(echo $DEFAULT_CONFIG_JSON | jq -rc $jq_expr | tr "\n" " "))
  fi
  if [ $? -ne 0 ]; then
    log "Error reading $jq_expr from config files"
    return 1
  fi
  echo "${config_array[@]}"
}

function validate_dns_section {
  set -o pipefail
  local jsonToValidate=$1
  local dnsType=$(get_config_value '.dns.type') || fail "Could not get dns type from config"
  if [ "$dnsType" == "external" ]; then
    #there should be an "external" section containing a suffix
    echo "$dnsJson" | jq '.external.suffix' || fail "For dns type external, a suffix is expected in section .dns.external.suffix of the config file"
  elif [ "$dnsType" == "oci" ]; then
    # TODO OCI related validation here?
    log "TODO OCI DNS Type validation"
  elif [ "$dnsType" != "xip.io" ]; then
    fail "Unknown dns type $dnsType - valid values are xip.io, oci and external"
  fi
}

# Make sure CONFIG_JSON and DEFAULT_CONFIG_JSON contain valid JSON
function validate_config_json {
  set -o pipefail
  local jsonToValidate=$1
  echo "$jsonToValidate" | jq > /dev/null || fail "Failed to read installation config file contents. Make sure it is valid JSON"

  validate_dns_section "$jsonToValidate"
}

function get_ingress_ip {
  local ingress_type=$(get_config_value ".ingress.type")
  if [ ${ingress_type} == "nodePort" ]; then
    get_ingress_ip=$(get_config_value ".ingress.nodePort.ingressIp")
  elif [ ${ingress_type} == "loadBalancer" ]; then
    # Test for IP from status, if that is not present then assume an on premises installation and use the externalIPs hint
    get_ingress_ip=$(kubectl get svc ingress-controller-nginx-ingress-controller -n ingress-nginx -o json | jq -r '.status.loadBalancer.ingress[0].ip')
    # In case of OLCNE, it would return null
    if [ ${get_ingress_ip} == "null" ]; then
      get_ingress_ip=$(kubectl get svc ingress-controller-nginx-ingress-controller -n ingress-nginx -o json  | jq -r '.spec.externalIPs[0]')
    fi
  fi
  echo ${get_ingress_ip}
}

function get_dns_suffix {
  local ingress_ip=$1
  local dns_type=$(get_config_value ".dns.type")
  if [ $dns_type == "xip.io" ]; then
    dns_suffix="${ingress_ip}".xip.io
  elif [ $dns_type == "oci" ]; then
    dns_suffix=$(get_config_value ".dns.oci.dnsZoneName")
  elif [ $dns_type == "external" ]; then
    dns_suffix=$(get_config_value ".dns.external.suffix")
  fi
  echo ${dns_suffix}
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

validate_config_json "$CONFIG_JSON" || fail "Installation config is invalid"
validate_config_json "$DEFAULT_CONFIG_FILECONFIG_JSON" || fail "Default installation config is invalid"

## Test cases - TODO remove before merging
#ENV_NAME=$(get_config_value ".environmentName")
#log "got environmentName value ${ENV_NAME}"
#EXTRA_ARG0=$(get_config_value ".ingress.verrazzano.extraInstallArgs[0]")
#log "status $? and got 0th extra argument value ${EXTRA_ARG0}"
#EXTRA_ARGS_ARR=($(get_config_array ".ingress.verrazzano.extraInstallArgs[]"))
#echo "status $? and got array [ ${EXTRA_ARGS_ARR[@]} ] containing ${EXTRA_ARGS_ARR[0]} and ${EXTRA_ARGS_ARR[1]}"