#!/usr/bin/env bash

echo "Getting AWS Users credentials from Vault"
AWS_ACCESS_KEY_ID="$(docker run -i \
                                --rm \
                                -v "${VAULT_READ_TOKEN_PATH}":/root/.vault-token \
                                -v "${PWD}":/working \
                                broadinstitute/dsde-toolbox:ra_rendering \
                                vault read -field='aws_access_key' secret/dsde/mint/${ENVIRONMENT}/lira/aws_cert_user)"
AWS_SECRET_ACCESS_KEY="$(docker run -i \
                                    --rm \
                                    -v "${VAULT_READ_TOKEN_PATH}":/root/.vault-token \
                                    -v "${PWD}":/working \
                                    broadinstitute/dsde-toolbox:ra_rendering \
                                    vault read -field='aws_secret_key' secret/dsde/mint/${ENVIRONMENT}/lira/aws_cert_user)"

echo "Making the temp directory for certs"
mkdir ${WORK_DIR}/certs

echo "Building the Certbot docker image"
cd "${DEPLOY_DIR}"
docker build -t certbot .

cd ${WORK_DIR}/certs

echo "Executing the certbot script to create a cert"
docker run \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
    -e DOMAIN="${DOMAIN}" \
    -v $(pwd):/certs \
    -v "${SCRIPTS_DIR}/certbot-route53.sh":/certs/certbot-route53.sh \
    -w /certs \
    --privileged \
    certbot:latest \
    bash -c \
        "bash /certs/certbot-route53.sh"

cd ${WORK_DIR}

sudo chown -R jenkins certs

function write_to_vault {
  file_name=$1
  live_or_archive=$2

  # strip number from filename
  vault_file_name=$(printf '%s\n' "${file_name//[[:digit:]]/}")

  FILE_TO_WRITE="certs/letsencrypt/${live_or_archive}/${DOMAIN}/${file_name}"
  VAULT_PATH="certs/letsencrypt/${live_or_archive}/${DOMAIN}/${vault_file_name}"

  echo "Writing cert with ${file_name} to vault at path ${VAULT_PATH}"
  docker run -i \
             --rm \
             -v "${VAULT_WRITE_TOKEN_PATH}":/root/.vault-token \
             -v "${PWD}":/working \
             broadinstitute/dsde-toolbox:ra_rendering \
             vault write "secret/dsde/mint/${ENVIRONMENT}/lira/${vault_file_name}" value=@"${FILE_TO_WRITE}"
}

function write_certs_to_vault {
  echo "writing certs to vault"

  for file_name in "fullchain1.pem" "privkey1.pem" "chain1.pem" "cert1.pem"
  do
    if [[ -f "certs/letsencrypt/live/${DOMAIN}/$(printf '%s\n' "${f//[[:digit:]]/}")"  ]]
    then
      file_name=$(printf '%s\n' "${file_name//[[:digit:]]/}")
      echo "${file_name} from live path"
      write_to_vault "${file_name}" "live"
    elif [[ -f "certs/letsencrypt/archive/${DOMAIN}/${file_name}" ]];
    then
      echo "${file_name} from archive path"
      write_to_vault "${file_name}" "archive"
    else
      echo "${file_name^} file doesn't exist. Skipping..."
    fi
  done
}

write_certs_to_vault

echo "Removing local copies of certs"
rm -rf certs
