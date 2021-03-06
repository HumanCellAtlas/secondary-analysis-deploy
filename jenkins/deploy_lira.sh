#!/usr/bin/env bash

export ENVIRONMENT=${BRANCH}

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/google-cloud-sdk/bin

export VAULT_READ_TOKEN_PATH="/etc/vault-token-mint-read"
export VAULT_WRITE_TOKEN_PATH="/etc/vault-token-mint-write"

export WORK_DIR=$(pwd)
export CONFIG_DIR=${WORK_DIR}/config_files
export DOCKER_CONFIG_DIR=/working/config_files
export DEPLOY_DIR=${WORK_DIR}/jenkins
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

# KUBERNETES SERVICE DEPLOYMENT

echo "Generating service file"
docker run -i --rm \
              -v "${VAULT_READ_TOKEN_PATH}":/root/.vault-token \
              -v "${PWD}":/working \
              broadinstitute/dsde-toolbox:ra_rendering \
              /usr/local/bin/render-ctmpls.sh \
              -k "${DOCKER_CONFIG_DIR}/lira-service.yaml.ctmpl"

echo "Deploying Lira Service"
kubectl apply -f ${CONFIG_DIR}/lira-service.yaml \
              --record \
              --namespace="${KUBERNETES_NAMESPACE}"

# TLS CERT GENERATION AND KUBERNETES INGRESS

if [[ ${GENERATE_CERTS} == "true" ]];
then
    echo "Generating TLS cert"
    sh "${DEPLOY_DIR}"/generate_certs.sh
fi

echo "Rendering TLS cert"
docker run -i --rm -e ENVIRONMENT="${ENVIRONMENT}" \
                   -v "${VAULT_READ_TOKEN_PATH}":/root/.vault-token:ro \
                   -v "${PWD}":/working \
                   --privileged \
                   broadinstitute/dsde-toolbox:ra_rendering \
                   /usr/local/bin/render-ctmpls.sh \
                   -k "${DOCKER_CONFIG_DIR}/${TLS_FULL_CHAIN_DIR}".ctmpl

echo "Rendering TLS key file"
docker run -i --rm -e ENVIRONMENT="${ENVIRONMENT}" \
                   -v "${VAULT_READ_TOKEN_PATH}":/root/.vault-token:ro \
                   -v "${PWD}":/working \
                   --privileged \
                   broadinstitute/dsde-toolbox:ra_rendering \
                   /usr/local/bin/render-ctmpls.sh \
                   -k "${DOCKER_CONFIG_DIR}/${TLS_PRIVATE_KEY_DIR}".ctmpl

echo "Creating TLS secret in Kubernetes"
kubectl create secret tls \
                "${TLS_SECRET_NAME}" \
                --cert="${CONFIG_DIR}/${TLS_FULL_CHAIN_DIR}" \
                --key="${CONFIG_DIR}/${TLS_PRIVATE_KEY_DIR}" \
                --namespace="${KUBERNETES_NAMESPACE}"

echo "LIRA_INGRESS_NAME=${LIRA_INGRESS_NAME}"
echo "LIRA_GLOBAL_IP_NAME=${LIRA_GLOBAL_IP_NAME}"
echo "TLS_SECRET_NAME=${TLS_SECRET_NAME}"
echo "LIRA_SERVICE_NAME=${LIRA_SERVICE_NAME}"

echo "Generating ingress file"
docker run -i --rm -e TLS_SECRET_NAME="${TLS_SECRET_NAME}" \
                   -v "${VAULT_READ_TOKEN_PATH}":/root/.vault-token \
                   -v "${PWD}":/working \
                   --privileged \
                   broadinstitute/dsde-toolbox:ra_rendering \
                   /usr/local/bin/render-ctmpls.sh \
                   -k "${DOCKER_CONFIG_DIR}/lira-ingress.yaml.ctmpl"

echo "Deploying Lira Ingress"
kubectl apply -f ${CONFIG_DIR}/lira-ingress.yaml \
              --record \
              --namespace="${KUBERNETES_NAMESPACE}"

# LIRA APPLICATION DEPLOYMENT

echo "Rendering lira config file"
docker run -i --rm \
              -e ENVIRONMENT="${ENVIRONMENT}" \
              -e CROMWELL_URL="${CROMWELL_URL}" \
              -e USE_CAAS="${USE_CAAS}" \
              -e SUBMIT_AND_HOLD="${SUBMIT_AND_HOLD}" \
              -e COLLECTION_NAME="${COLLECTION_NAME}" \
              -e GCLOUD_PROJECT="${GCLOUD_PROJECT}" \
              -e GCS_ROOT="${GCS_ROOT}" \
              -e LIRA_VERSION="${LIRA_VERSION}" \
              -e DSS_URL="${DSS_URL}" \
              -e SCHEMA_URL="${SCHEMA_URL}" \
              -e INGEST_URL="${INGEST_URL}" \
              -e USE_HMAC="${USE_HMAC}" \
              -e SUBMIT_WDL="${SUBMIT_WDL}" \
              -e MAX_CROMWELL_RETRIES="${MAX_CROMWELL_RETRIES}" \
              -e TENX_ANALYSIS_WDLS="${TENX_ANALYSIS_WDLS}" \
              -e TENX_OPTIONS_LINK="${TENX_OPTIONS_LINK}" \
              -e TENX_SUBSCRIPTION_ID="${TENX_SUBSCRIPTION_ID}" \
              -e TENX_WDL_STATIC_INPUTS_LINK="${TENX_WDL_STATIC_INPUTS_LINK}" \
              -e TENX_WDL_LINK="${TENX_WDL_LINK}" \
              -e TENX_WORKFLOW_NAME="${TENX_WORKFLOW_NAME}" \
              -e TENX_VERSION="${TENX_VERSION}" \
              -e SS2_ANALYSIS_WDLS="${SS2_ANALYSIS_WDLS}" \
              -e SS2_OPTIONS_LINK="${SS2_OPTIONS_LINK}" \
              -e SS2_SUBSCRIPTION_ID="${SS2_SUBSCRIPTION_ID}" \
              -e SS2_WDL_STATIC_INPUTS_LINK="${SS2_WDL_STATIC_INPUTS_LINK}" \
              -e SS2_WDL_LINK="${SS2_WDL_LINK}" \
              -e SS2_WORKFLOW_NAME="${SS2_WORKFLOW_NAME}" \
              -e SS2_VERSION="${SS2_VERSION}" \
              -v "${VAULT_READ_TOKEN_PATH}":/root/.vault-token \
              -v "${PWD}":/working \
              --privileged \
              broadinstitute/dsde-toolbox:ra_rendering \
              /usr/local/bin/render-ctmpls.sh \
              -k "${DOCKER_CONFIG_DIR}/${LIRA_CONFIG_FILE}.ctmpl"

echo "Deploying lira config file"
if [[ "${USE_CAAS}" == "true" ]];
then
    kubectl create secret generic "${LIRA_CONFIG_SECRET_NAME}" \
            --from-file=config="${CONFIG_DIR}/${LIRA_CONFIG_FILE}" \
            --from-file=caas_key="${CONFIG_DIR}/${CAAS_KEY_FILE}" \
            --namespace "${KUBERNETES_NAMESPACE}"
else
    kubectl create secret generic "${LIRA_CONFIG_SECRET_NAME}" \
            --from-file=config="${CONFIG_DIR}/${LIRA_CONFIG_FILE}" \
            --namespace "${KUBERNETES_NAMESPACE}"
fi

echo "Generating Lira deployment file"
docker run -i --rm -e LIRA_CONFIG_SECRET_NAME="${LIRA_CONFIG_SECRET_NAME}" \
                   -e LIRA_DOCKER_IMAGE="${LIRA_DOCKER_IMAGE}" \
                   -e USE_CAAS="${USE_CAAS}" \
                   -v "${VAULT_READ_TOKEN_PATH}":/root/.vault-token \
                   -v "${PWD}":/working \
                   --privileged \
                   broadinstitute/dsde-toolbox:ra_rendering \
                   /usr/local/bin/render-ctmpls.sh \
                   -k "${DOCKER_CONFIG_DIR}/${LIRA_DEPLOYMENT_YAML}.ctmpl"

echo "Deploying Lira"
kubectl apply -f ${CONFIG_DIR}/lira-deployment.yaml \
              --record \
              --namespace "${KUBERNETES_NAMESPACE}"

#echo "Generating Lira autoscaler file"
#docker run -i --rm -e LIRA_AUTOSCALER_NAME="${LIRA_AUTOSCALER_NAME}" \
#                   -e LIRA_DEPLOYMENT_NAME= "${LIRA_DEPLOYMENT_NAME}" \
#                   -e LIRA_MIN_REPLICAS="${LIRA_MIN_REPLICAS}" \
#                   -e LIRA_MAX_REPLICAS="${LIRA_MAX_REPLICAS}" \
#                   -e LIRA_PERCENT_TARGET_CPU_USAGE="${LIRA_PERCENT_TARGET_CPU_USAGE}" \
#                   -v "${VAULT_READ_TOKEN_PATH}":/root/.vault-token \
#                   -v "${PWD}":/working \
#                   --privileged \
#                   broadinstitute/dsde-toolbox:ra_rendering \
#                   /usr/local/bin/render-ctmpls.sh \
#                    -k "${DOCKER_CONFIG_DIR}/lira-autoscaler.yaml.ctmpl"
#
#cat "${CONFIG_DIR}/lira-autoscaler.yaml"
#
#echo "Deploying Lira autoscaler"
#kubectl apply -f "${CONFIG_DIR}/lira-autoscaler.yaml" \
#              --record \
#              --namespace "${KUBERNETES_NAMESPACE}"
