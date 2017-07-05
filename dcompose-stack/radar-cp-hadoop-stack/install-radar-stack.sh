#!/bin/bash

. ./util.sh
. ./.env

check_parent_exists HDFS_DATA_DIR_1 ${HDFS_DATA_DIR_1}
check_parent_exists HDFS_DATA_DIR_2 ${HDFS_DATA_DIR_2}
check_parent_exists HDFS_NAME_DIR_1 ${HDFS_NAME_DIR_1}
check_parent_exists HDFS_NAME_DIR_2 ${HDFS_NAME_DIR_2}
check_parent_exists MONGODB_DIR ${MONGODB_DIR}

if [ -z ${SERVER_NAME} ]; then
  echo "Set SERVER_NAME variable in .env"
  exit 1
fi

if [ -z $(sudo-linux docker network ls --format '{{.Name}}' | grep "^hadoop$") ]; then
  echo "==> Creating docker network - hadoop"
  sudo-linux docker network create hadoop > /dev/null
else
  echo "==> Creating docker network - hadoop ALREADY EXISTS"
fi

echo "==> Configuring MongoDB Connector"

# Update sink-mongo.properties
copy_template_if_absent etc/sink-mongo.properties
inline_variable 'mongo.username=' $HOTSTORAGE_USERNAME etc/sink-mongo.properties
inline_variable 'mongo.password=' $HOTSTORAGE_PASSWORD etc/sink-mongo.properties
inline_variable 'mongo.database=' $HOTSTORAGE_NAME etc/sink-mongo.properties

# Set topics
inline_variable 'topics=' "${RADAR_AGG_TOPIC_LIST}" etc/sink-mongo.properties

echo "==> Configuring HDFS Connector"
copy_template_if_absent etc/sink-hdfs.properties
inline_variable 'topics=' "${RADAR_RAW_TOPIC_LIST}" etc/sink-hdfs.properties

echo "==> Configuring REST-API"
copy_template_if_absent etc/rest-api/radar.yml
copy_template_if_absent etc/rest-api/device-catalog.yml
copy_template_if_absent etc/rest-api/radar-is.yml

# Set MongoDb credential
inline_variable 'usr:[[:space:]]' $HOTSTORAGE_USERNAME etc/rest-api/radar.yml
inline_variable 'pwd:[[:space:]]' $HOTSTORAGE_PASSWORD etc/rest-api/radar.yml
inline_variable 'db:[[:space:]]' $HOTSTORAGE_NAME etc/rest-api/radar.yml

# Set variable for Swagger
inline_variable 'host:[[:space:]]*' "${SERVER_NAME}" etc/rest-api/radar.yml

# Set identity server configuration
inline_variable 'username:[[:space:]]*' "${RADAR_IS_USERNAME}" etc/rest-api/radar-is.yml
inline_variable 'password:[[:space:]]*' "${RADAR_IS_PASSWORD}" etc/rest-api/radar-is.yml
inline_variable 'tokenValidationEndpoint:[[:space:]]*' "${RADAR_IS_TOKEN_VALIDATION_ENDPOINT}" etc/rest-api/radar-is.yml
inline_variable 'publicKeyEndpoint:[[:space:]]*' "${RADAR_IS_PUBLIC_KEY_ENDPOINT}" etc/rest-api/radar-is.yml

echo "==> Configuring nginx"
copy_template_if_absent etc/nginx.conf
inline_variable 'server_name[[:space:]]*' "${SERVER_NAME};" etc/nginx.conf
sed_i 's|\(/etc/letsencrypt/live/\)[^/]*\(/.*\.pem\)|\1'"${SERVER_NAME}"'\2|' etc/nginx.conf
init_certificate "${SERVER_NAME}"

echo "==> Starting RADAR-CNS Platform"
sudo-linux docker-compose up --force-recreate -d "$@"

request_certificate "${SERVER_NAME}" "${SELF_SIGNED_CERT:-yes}"
echo "### SUCCESS ###"
