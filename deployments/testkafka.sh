#!/bin/sh

dir="$(dirname "$(realpath "$0")")"
client_properties_path="$dir"/client.properties

kubectl run kafka-client --restart='Never' --image localhost:5001/bitnami/kafka:3.7.0-debian-12-r2 --namespace default --command -- sleep infinity && \
    sleep 5 && \
    kubectl cp --namespace default "$client_properties_path" kafka-client:/tmp/client.properties && \
    kubectl exec --tty -i kafka-client --namespace default -- bash
