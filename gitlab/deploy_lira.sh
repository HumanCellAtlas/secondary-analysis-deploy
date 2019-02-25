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

echo "Retrieving caas service account key"
vault read -format=json "${CAAS_KEY_PATH}" | jq .data > "${CONFIG_DIR}/${CAAS_KEY_FILE}"

echo "Authenticating with the service account"
gcloud auth activate-service-account --key-file "${CONFIG_DIR}/${CAAS_KEY_FILE}"

echo "Getting kubernetes context"
gcloud container clusters get-credentials "${KUBERNETES_CLUSTER}" \
                 --zone "${KUBERNETES_ZONE}" \
                 --project "${GCLOUD_PROJECT}"


# KUBERNETES SERVICE DEPLOYMENT

echo "LIRA_SERVICE_NAME=${LIRA_SERVICE_NAME}"
echo "LIRA_APPLICATION_NAME=${LIRA_APPLICATION_NAME}"

echo "Generating Lira service file"
sh "${DEPLOY_DIR}/render-ctmpls.sh" -k "${CONFIG_DIR}/lira-service.yaml.ctmpl"

cat "${CONFIG_DIR}/lira-service.yaml"

echo "Deploying Lira Service"
kubectl apply -f ${CONFIG_DIR}/lira-service.yaml \
              --record \
              --namespace="${KUBERNETES_NAMESPACE}"


# TLS CERT GENERATION AND KUBERNETES INGRESS

if [ "${GENERATE_CERTS}" == "true" ];
then
    sh "${DEPLOY_DIR}/generate_certs.sh"
fi

echo "Rendering TLS cert"
sh "${DEPLOY_DIR}/render-ctmpls.sh" -k "${CONFIG_DIR}/${TLS_FULL_CHAIN_DIR}.ctmpl"

echo "Rendering TLS key file"
sh "${DEPLOY_DIR}/render-ctmpls.sh" -k "${CONFIG_DIR}/${TLS_PRIVATE_KEY_DIR}.ctmpl"

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
sh "${DEPLOY_DIR}/render-ctmpls.sh" -k "${CONFIG_DIR}/lira-ingress.yaml.ctmpl"

cat "${CONFIG_DIR}/lira-ingress.yaml"

echo "Deploying Lira Ingress"
kubectl apply -f ${CONFIG_DIR}/lira-ingress.yaml \
              --record \
              --namespace="${KUBERNETES_NAMESPACE}"



# LIRA APPLICATION DEPLOYMENT

echo "ENVIRONMENT=${ENVIRONMENT}"
echo "CROMWELL_URL=${CROMWELL_URL}"
echo "USE_CAAS=${USE_CAAS}"
echo "COLLECTION_NAME=${COLLECTION_NAME}"
echo "GCLOUD_PROJECT=${GCLOUD_PROJECT}"
echo "GCS_ROOT=${GCS_ROOT}"
echo "DOMAIN=${DOMAIN}"
echo "LIRA_VERSION=${LIRA_VERSION}"
echo "SUBMIT_AND_HOLD=${SUBMIT_AND_HOLD}"
echo "DSS_URL=${DSS_URL}"
echo "SCHEMA_URL=${SCHEMA_URL}"
echo "INGEST_URL=${INGEST_URL}"
echo "USE_HMAC=${USE_HMAC}"
echo "MAX_CROMWELL_RETRIES=${MAX_CROMWELL_RETRIES}"
echo "SUBMIT_WDL=${SUBMIT_WDL}"
echo "TENX_ANALYSIS_WDLS=${TENX_ANALYSIS_WDLS}"
echo "TENX_OPTIONS_LINK=${TENX_OPTIONS_LINK}"
echo "TENX_SUBSCRIPTION_ID=${TENX_SUBSCRIPTION_ID}"
echo "TENX_WDL_STATIC_INPUTS_LINK=${TENX_WDL_STATIC_INPUTS_LINK}"
echo "TENX_WDL_LINK=${TENX_WDL_LINK}"
echo "TENX_OPTIONS_LINK=${TENX_OPTIONS_LINK}"
echo "TENX_SUBSCRIPTION_ID=${TENX_SUBSCRIPTION_ID}"
echo "TENX_WORKFLOW_NAME=${TENX_WORKFLOW_NAME}"
echo "TENX_VERSION=${TENX_VERSION}"
echo "SS2_ANALYSIS_WDLS=${SS2_ANALYSIS_WDLS}"
echo "SS2_OPTIONS_LINK=${SS2_OPTIONS_LINK}"
echo "SS2_SUBSCRIPTION_ID=${SS2_SUBSCRIPTION_ID}"
echo "SS2_WDL_STATIC_INPUTS_LINK=${SS2_WDL_STATIC_INPUTS_LINK}"
echo "SS2_WDL_LINK=${SS2_WDL_LINK}"
echo "SS2_WORKFLOW_NAME=${SS2_WORKFLOW_NAME}"
echo "SS2_VERSION=${SS2_VERSION}"

echo "Rendering lira config file"
sh "${DEPLOY_DIR}/render-ctmpls.sh" -k "${CONFIG_DIR}/${LIRA_CONFIG_FILE}.ctmpl"

echo "Deploying lira config file"
if [ "${USE_CAAS}" == "true" ];
then
    kubectl create secret generic "${LIRA_CONFIG_SECRET_NAME}" \
            --from-file=config="${CONFIG_DIR}/${LIRA_CONFIG_FILE}" \
            --from-file=caas_key="${CONFIG_DIR}/${CAAS_KEY_FILE}" \
            --namespace "${KUBERNETES_NAMESPACE}"
else
    kubectl create secret generic ${LIRA_CONFIG_SECRET_NAME} \
            --from-file=config="${CONFIG_DIR}/${LIRA_CONFIG_FILE}" \
            --namespace "${KUBERNETES_NAMESPACE}"
fi

echo "Generating Lira deployment file"
sh "${DEPLOY_DIR}/render-ctmpls.sh" -k "${CONFIG_DIR}/${LIRA_DEPLOYMENT_YAML}.ctmpl"

cat "${CONFIG_DIR}/${LIRA_DEPLOYMENT_YAML}"

echo "Deploying Lira"
kubectl apply -f "${CONFIG_DIR}/${LIRA_DEPLOYMENT_YAML}" \
              --record \
              --namespace "${KUBERNETES_NAMESPACE}"
