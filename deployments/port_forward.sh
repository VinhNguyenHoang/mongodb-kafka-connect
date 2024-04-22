#!/bin/bash

# forward port for mongodb
kubectl -n default port-forward svc/mongodb-headless 27017:27017 & \
    # forward port for mongodb2
    kubectl -n default port-forward svc/mongodb2-headless 27018:27017 & \
    # forward port for kafka-connect
    kubectl -n default port-forward svc/kafka-connect 8083:8083

wait