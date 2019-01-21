#!/usr/bin/env bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/google-cloud-sdk/bin

export VAULT_READ_TOKEN_PATH="/gitlab-runner/.vault-read-token"
export VAULT_TOKEN="$(cat ${VAULT_READ_TOKEN_PATH})"

export WORK_DIR=$(pwd)
export CONFIG_DIR=${WORK_DIR}/config_files
export DEPLOY_DIR=${WORK_DIR}/gitlab
export SCRIPTS_DIR=${WORK_DIR}/scripts

echo "Rendering deployment configuration file"
sh "${DEPLOY_DIR}/render-ctmpls.sh" -k "${CONFIG_DIR}/config.sh.ctmpl"

# Import the variables from the config files
source "${CONFIG_DIR}/config.sh"

echo "Retrieving caas service account key"
vault read -format=json "${CAAS_KEY_PATH}" | jq .data > "${CONFIG_DIR}/${CAAS_KEY_FILE}"

echo "Authenticating with the service account"
gcloud auth activate-service-account --key-file "${CONFIG_DIR}/${CAAS_KEY_FILE}"

echo "Getting kubernetes context"
gcloud container clusters get-credentials "${KUBERNETES_CLUSTER}" \
                 --zone "${KUBERNETES_ZONE}" \
                 --project "${GCLOUD_PROJECT}"

# FALCON APPLICATION DEPLOYMENT

echo "Rendering falcon config file"
sh "${DEPLOY_DIR}/render-ctmpls.sh" -k "${CONFIG_DIR}/${FALCON_CONFIG_FILE}.ctmpl"

echo "Deploying falcon config file"
#if [ "${USE_CAAS}" == "true" ];
#then
#    kubectl create secret generic "${FALCON_CONFIG_SECRET_NAME}" \
#            --from-file=config="${CONFIG_DIR}/${FALCON_CONFIG_FILE}" \
#            --from-file=caas_key="${CONFIG_DIR}/${CAAS_KEY_FILE}" \
#            --namespace "${KUBERNETES_NAMESPACE}"
#else
#    kubectl create secret generic ${FALCON_CONFIG_SECRET_NAME} \
#            --from-file=config="${CONFIG_DIR}/${FALCON_CONFIG_FILE}" \
#            --namespace "${KUBERNETES_NAMESPACE}"
#fi

echo "Generating Falcon deployment file"
sh "${DEPLOY_DIR}/render-ctmpls.sh" -k "${CONFIG_DIR}/${FALCON_DEPLOYMENT_YAML}.ctmpl"

echo "Deploying Falcon"
#kubectl apply -f "${CONFIG_DIR}/${FALCON_DEPLOYMENT_YAML}" \
#              --record \
#              --namespace "${KUBERNETES_NAMESPACE}"