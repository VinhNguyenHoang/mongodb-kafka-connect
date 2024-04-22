#!/bin/bash

BITNAMI_MGO_IMG="bitnami/mongodb:7.0.3-debian-11-r6"
BITNAMI_KAFKA_IMG="bitnami/kafka:3.7.0-debian-12-r2"

REGISTRY_REPO="docker.io"
REGISTRY_HOST="localhost:5001"

image_names=(
    "$BITNAMI_MGO_IMG"
    "$BITNAMI_KAFKA_IMG"
)

for img_name in "${image_names[@]}"; do
    # Check if the image exists in the local Docker registry
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q $REGISTRY_HOST/"$img_name"; then
        echo "Image $img_name exists in the local machine"
    else
        echo "Image $img_name does not exist in the local machine, pulling..."
        # Pull the image if it doesn't exist locally
        docker pull $REGISTRY_REPO/"$img_name"
        docker tag $REGISTRY_REPO/"$img_name" $REGISTRY_HOST/"$img_name"
        docker push $REGISTRY_HOST/"$img_name"
    fi
done