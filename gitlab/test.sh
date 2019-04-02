#!/usr/bin/env bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/google-cloud-sdk/bin

export VAULT_READ_TOKEN_PATH="/gitlab-runner/vault-token-mint-read"
export VAULT_WRITE_TOKEN_PATH="/gitlab-runner/vault-token-mint-write"
export VAULT_TOKEN="$(cat ${VAULT_READ_TOKEN_PATH})"

export WORK_DIR=$(pwd)
export CONFIG_DIR=${WORK_DIR}/config_files
export DEPLOY_DIR=${WORK_DIR}/gitlab
export SCRIPTS_DIR=${WORK_DIR}/scripts

echo "Rendering deployment configuration file"
sh "${DEPLOY_DIR}/render-ctmpls.sh" -k "${CONFIG_DIR}/config.sh.ctmpl"

# Import the variables from the config files
source "${CONFIG_DIR}/config.sh"