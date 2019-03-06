#!/usr/bin/env bash

# Please Note: the dss storage service white list may need to be updated
# (https://github.com/HumanCellAtlas/data-store/blob/master/environment#L63) to include the
# bluebox-subscription-manager@<GCLOUD_PROJECT>.iam.gserviceaccount.com service account

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

echo "Setting the GCloud project"
gcloud config set project ${GCLOUD_PROJECT}

echo "Creating bluebox-subscription-manager service account and key"
gcloud iam service-accounts create bluebox-subscription-manager --display-name=bluebox-subscription-manager
gcloud iam service-accounts keys create ${BLUEBOX_SUBSCRIPTION_KEY} --iam-account=${BLUEBOX_IAM_ACCOUNT}

echo "Getting current bluebox service account key from vault"














echo "Adding service account key to vault"
vault write "${BLUEBOX_SUBSCRIPTION_PATH}" @/working/"${BLUEBOX_SUBSCRIPTION_KEY}"

echo "Getting the HMAC key from vault"
vault read -format=json "${HMAC_KEY_PATH}" > "${HMAC_KEY_FILE}"



echo "Creating ss2 subscription"
SS2_SUBSCRIPTION_ID=$(python3 subscribe.py create --dss_url="${DSS_URL}" \
                            --key_file="${BLUEBOX_KEY_PATH}" \
                            --google_project="${GCLOUD_PROJECT}" \
                            --replica="gcp" \
                            --callback_base_url="${LIRA_URL}" \
                            --query_json="${SMART_SEQ_2_QUERY}" \
                            --hmac_key_id="$(cat ${HMAC_KEY_FILE} | jq .data | jq 'keys[]')" \
                            --hmac_key="$(cat ${HMAC_KEY_FILE} | jq .data | jq 'values[]')" \
                            --additional_metadata="${ADDITIONAL_METADATA}")

echo "${SS2_SUBSCRIPTION_ID}"

echo "Creating 10x subscription"
TENX_SUBSCRIPTION_ID=$(python3 subscribe.py create --dss_url="${DSS_URL}" \
                            --key_file="${BLUEBOX_KEY_PATH}" \
                            --google_project="${GCLOUD_PROJECT}" \
                            --replica="gcp" \
                            --callback_base_url="${LIRA_URL}" \
                            --query_json="${TENX_QUERY}" \
                            --hmac_key_id="$(cat ${HMAC_KEY_FILE} | jq .data | jq 'keys[]')" \
                            --hmac_key="$(cat ${HMAC_KEY_FILE} | jq .data | jq 'values[]')" \
                            --additional_metadata="${ADDITIONAL_METADATA}")

echo "${TENX_SUBSCRIPTION_ID}"
