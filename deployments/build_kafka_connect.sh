#!/bin/sh

DOCKERFILE_PATH="kafkaconnect.Dockerfile"
IMAGE_NAME="kafka-connect"
REGISTRY_HOST="localhost:5001"
REGISTRY_REPO="bitnami"

dir="$(dirname "$(realpath "$0")")"

IMAGE_FULL_PATH=$REGISTRY_HOST/$REGISTRY_REPO/$IMAGE_NAME":latest"

docker build -t $IMAGE_FULL_PATH -f "$dir/"$DOCKERFILE_PATH . --no-cache

docker push $IMAGE_FULL_PATH