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

  echo "Writing ${file_name} to vault at path ${VAULT_PATH}"
  docker run -i \
             --rm \
             -v "${VAULT_WRITE_TOKEN_PATH}":/root/.vault-token \
             -v "${PWD}":/working \
             broadinstitute/dsde-toolbox:ra_rendering \
             vault write "secret/dsde/mint/${ENVIRONMENT}/lira/${vault_file_name}" value=@"${FILE_TO_WRITE}"
}

function write_certs_to_vault {
  echo "writing certs to vault"

  for f in "fullchain1.pem" "privkey1.pem" "chain1.pem" "cert1.pem"
  do
    if [[ -f "certs/letsencrypt/live/${DOMAIN}/$(printf '%s\n' "${f//[[:digit:]]/}")"  ]]
    then
      echo "${f} from new cert"
      write_to_vault "${f}" "live"
    elif [[ -f "certs/letsencrypt/archive/${DOMAIN}/${f}" ]];
    then
      echo "${f} from new cert"
      write_to_vault "${f}" "archive"
    else
      echo "${f^} file doesn't exist. Skipping..."
    fi
  done
}


echo "--------------------------------------------------"
echo "entering write to vault function"
write_certs_to_vault
echo "done with write to vault function"
echo "--------------------------------------------------"


#  if [[ -f "certs/letsencrypt/archive/${DOMAIN}/fullchain1.pem" ]];
#  then
#      write_to_vault "fullchain1.pem" "archive"
#
#  elif [[ -f "certs/letsencrypt/live/${DOMAIN}/fullchain.pem"  ]]
#  then
#      write_to_vault "fullchain1.pem" "live"
#
#  else
#      echo "Fullchain file doesn't exist. Skipping..."
#  fi
#
#
#  if [[ -f "certs/letsencrypt/archive/${DOMAIN}/privkey1.pem" ]];
#  then
#      write_to_vault "privkey1.pem" "archive"
#  elif [[ -f "certs/letsencrypt/live/${DOMAIN}/privkey.pem"  ]]
#  then
#      write_to_vault "privkey1.pem" "archive"
#  else
#      echo "Private key file doesn't exist. Skipping..."
#  fi
#
#
#  if [[ -f "certs/letsencrypt/archive/${DOMAIN}/chain1.pem" ]];
#  then
#      write_to_vault "chain1.pem" "archive"
#  elif [[ -f "certs/letsencrypt/live/${DOMAIN}/chain.pem"  ]]
#  then
#      write_to_vault "chain1.pem" "archive"
#  else
#      echo "Chain file doesn't exist. Skipping..."
#  fi
#
#
#  if [[ -f "certs/letsencrypt/archive/${DOMAIN}/cert1.pem" ]];
#  then
#      write_to_vault "cert1.pem" "archive"
#  elif [[ -f "certs/letsencrypt/live/${DOMAIN}/cert.pem"  ]]
#  then
#      write_to_vault "cert1.pem" "archive"
#  else
#      echo "Cert file doesn't exist. Skipping..."
#  fi
}

#if [[ -f "certs/letsencrypt/archive/${DOMAIN}/fullchain1.pem" ]];
#then
#    FULLCHAIN_VAULT_DIR="certs/letsencrypt/archive/${DOMAIN}/fullchain1.pem"
#    echo "Writing fullchain to vault at ${FULLCHAIN_VAULT_DIR}"
#    docker run -i \
#               --rm \
#               -v "${VAULT_WRITE_TOKEN_PATH}":/root/.vault-token \
#               -v "${PWD}":/working \
#               broadinstitute/dsde-toolbox:ra_rendering \
#               vault write "secret/dsde/mint/${ENVIRONMENT}/lira/fullchain.pem" value=@"${FULLCHAIN_VAULT_DIR}"
#elif [[ -f "certs/letsencrypt/live/${DOMAIN}/fullchain.pem"  ]]
#then
#    FULLCHAIN_VAULT_DIR="certs/letsencrypt/live/${DOMAIN}/fullchain.pem"
#    echo "Writing fullchain to vault at ${FULLCHAIN_VAULT_DIR}"
#    docker run -i \
#               --rm \
#               -v "${VAULT_WRITE_TOKEN_PATH}":/root/.vault-token \
#               -v "${PWD}":/working \
#               broadinstitute/dsde-toolbox:ra_rendering \
#               vault write "secret/dsde/mint/${ENVIRONMENT}/lira/fullchain.pem" value=@"${FULLCHAIN_VAULT_DIR}"
#else
#    echo "Fullchain file doesn't exist. Skipping..."
#fi
#
#if [[ -f "certs/letsencrypt/archive/${DOMAIN}/privkey1.pem" ]];
#then
#    PRIVKEY_VAULT_DIR="certs/letsencrypt/archive/${DOMAIN}/privkey1.pem"
#    echo "Writing privkey to vault at secret/dsde/mint/${ENVIRONMENT}/lira/privkey.pem"
#    docker run -i \
#               --rm \
#               -v "${VAULT_WRITE_TOKEN_PATH}":/root/.vault-token \
#               -v "${PWD}":/working \
#               broadinstitute/dsde-toolbox:ra_rendering \
#               vault write "secret/dsde/mint/${ENVIRONMENT}/lira/privkey.pem" value=@"${PRIVKEY_VAULT_DIR}"
#elif [[ -f "certs/letsencrypt/live/${DOMAIN}/privkey.pem"  ]]
#then
#    FULLCHAIN_VAULT_DIR="certs/letsencrypt/live/${DOMAIN}/fullchain.pem"
#    echo "Writing fullchain to vault at ${FULLCHAIN_VAULT_DIR}"
#    docker run -i \
#               --rm \
#               -v "${VAULT_WRITE_TOKEN_PATH}":/root/.vault-token \
#               -v "${PWD}":/working \
#               broadinstitute/dsde-toolbox:ra_rendering \
#               vault write "secret/dsde/mint/${ENVIRONMENT}/lira/fullchain.pem" value=@"${FULLCHAIN_VAULT_DIR}"
#else
#    echo "Private key file doesn't exist. Skipping..."
#fi
#
#if [[ -f "certs/letsencrypt/archive/${DOMAIN}/chain1.pem" ]];
#then
#    CHAIN_VAULT_DIR="certs/letsencrypt/archive/${DOMAIN}/chain1.pem"
#    echo "Writing chain to vault at secret/dsde/mint/${ENVIRONMENT}/lira/chain.pem"
#    docker run -i \
#               --rm \
#               -v "${VAULT_WRITE_TOKEN_PATH}":/root/.vault-token \
#               -v "${PWD}":/working \
#               broadinstitute/dsde-toolbox:ra_rendering \
#               vault write "secret/dsde/mint/${ENVIRONMENT}/lira/chain.pem" value=@"${CHAIN_VAULT_DIR}"
#else
#    echo "Chain file doesn't exist. Skipping..."
#fi
#
#if [[ -f "certs/letsencrypt/archive/${DOMAIN}/cert1.pem" ]];
#then
#    CERT_VAULT_DIR="certs/letsencrypt/archive/${DOMAIN}/cert1.pem"
#    echo "Writing cert to vault at ${CERT_VAULT_DIR}"
#    docker run -i \
#               --rm \
#               -v "${VAULT_WRITE_TOKEN_PATH}":/root/.vault-token \
#               -v "${PWD}":/working \
#               broadinstitute/dsde-toolbox:ra_rendering \
#               vault write "secret/dsde/mint/${ENVIRONMENT}/lira/cert.pem" value=@"${CERT_VAULT_DIR}"
#else
#    echo "Cert file doesn't exist. Skipping..."
#fi

echo "Removing local copies of certs"
#rm -rf certs
