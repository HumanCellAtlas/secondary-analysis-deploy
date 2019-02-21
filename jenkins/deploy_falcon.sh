#!/usr/bin/env bash

export ENVIRONMENT=${BRANCH}

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/google-cloud-sdk/bin

export VAULT_READ_TOKEN_PATH="/etc/vault-token-mint-read"

export WORK_DIR=$(pwd)
export CONFIG_DIR=${WORK_DIR}/config_files
export DOCKER_CONFIG_DIR=/working/config_files
export DEPLOY_DIR=${WORK_DIR}/gitlab
export SCRIPTS_DIR=${WORK_DIR}/scripts

echo "Rendering deployment configuration file"
docker run -i --rm \
               -v "${VAULT_READ_TOKEN_PATH}":/root/.vault-token \
               -v "${PWD}":/working \
               -e ENVIRONMENT="${ENVIRONMENT}" \
               --privileged \
               broadinstitute/dsde-toolbox:ra_rendering \
               /usr/local/bin/render-ctmpls.sh \
               -k "${DOCKER_CONFIG_DIR}/config.sh.ctmpl"

# Import the variables from the config files
source "${CONFIG_DIR}/config.sh"

echo "Retrieving caas service account key"
docker run -i --rm \
               -v "${VAULT_READ_TOKEN_PATH}":/root/.vault-token \
               -v "${PWD}":/working \
               broadinstitute/dsde-toolbox:ra_rendering \
               vault read -format=json "${CAAS_KEY_PATH}" | jq .data > "${CONFIG_DIR}/${CAAS_KEY_FILE}"

echo "Authenticating with the service account"
gcloud auth activate-service-account --key-file "${CONFIG_DIR}/${CAAS_KEY_FILE}"

echo "Getting kubernetes context"
gcloud container clusters get-credentials "${KUBERNETES_CLUSTER}" \
                 --zone "${KUBERNETES_ZONE}" \
                 --project "${GCLOUD_PROJECT}"

# FALCON APPLICATION DEPLOYMENT

echo "Rendering falcon config file"
docker run -i --rm \
              -e ENVIRONMENT="${ENVIRONMENT}" \
              -e CROMWELL_URL="${CROMWELL_URL}" \
              -e USE_CAAS="${USE_CAAS}" \
              -e COLLECTION_NAME="${COLLECTION_NAME}" \
              -e FALCON_QUEUE_UPDATE_INTERVAL="${FALCON_QUEUE_UPDATE_INTERVAL}" \
              -e FALCON_WORKFLOW_START_INTERVAL="${FALCON_WORKFLOW_START_INTERVAL}" \
              -v "${VAULT_READ_TOKEN_PATH}":/root/.vault-token \
              -v "${PWD}":/working \
              --privileged \
              broadinstitute/dsde-toolbox:ra_rendering \
              /usr/local/bin/render-ctmpls.sh \
              -k "${DOCKER_CONFIG_DIR}/${FALCON_CONFIG_FILE}.ctmpl"

echo "Deploying falcon config file"
if [ "${USE_CAAS}" == "true" ];
then
    kubectl create secret generic "${FALCON_CONFIG_SECRET_NAME}" \
            --from-file=config="${CONFIG_DIR}/${FALCON_CONFIG_FILE}" \
            --from-file=caas_key="${CONFIG_DIR}/${CAAS_KEY_FILE}" \
            --namespace "${KUBERNETES_NAMESPACE}"
else
    kubectl create secret generic ${FALCON_CONFIG_SECRET_NAME} \
            --from-file=config="${CONFIG_DIR}/${FALCON_CONFIG_FILE}" \
            --namespace "${KUBERNETES_NAMESPACE}"
fi

echo "Generating Falcon deployment file"
docker run -i --rm \
              -e FALCON_DEPLOYMENT_NAME="${FALCON_DEPLOYMENT_NAME}" \
              -e FALCON_NUMBER_OF_REPLICAS="${FALCON_NUMBER_OF_REPLICAS}" \
              -e FALCON_APPLICATION_NAME="${FALCON_APPLICATION_NAME}" \
              -e FALCON_CONTAINER_NAME="${FALCON_CONTAINER_NAME}" \
              -e FALCON_DOCKER_IMAGE="${FALCON_DOCKER_IMAGE}" \
              -e USE_CAAS="${USE_CAAS}" \
              -e FALCON_CONFIG_SECRET_NAME="${FALCON_CONFIG_SECRET_NAME}" \
              -v "${VAULT_READ_TOKEN_PATH}":/root/.vault-token \
              -v "${PWD}":/working \
              --privileged \
              broadinstitute/dsde-toolbox:ra_rendering \
              /usr/local/bin/render-ctmpls.sh \
              -k "${DOCKER_CONFIG_DIR}/${FALCON_DEPLOYMENT_YAML}.ctmpl"

echo "Deploying Falcon"
kubectl apply -f "${CONFIG_DIR}/${FALCON_DEPLOYMENT_YAML}" \
              --record \
              --namespace "${KUBERNETES_NAMESPACE}"