# mongodb-kafka-connect

Demo mongodb and kafka connect setup

## Prerequisites

This guide is using registry address `localhost:5001` for local registry v2.

- Kubernetes 1.23+
- Helm 3.8.0+
- Kind 0.22.0+
- Go 1.21.0+

## Setup images and Kubernetes

Start Kubernetes cluster:

```
$ ./deployments/kind-with-registry.sh
```

To avoid long bootstrap time of the DB clusters and services, we should pre-pull images to the localhost.

We will use these images:

- bitnami/mongodb:7.0.3-debian-11-r6
- bitnami/kafka:3.7.0-debian-12-r2

Run this command to check if the images exist in the local machine, and then pull them:

```
$ ./deployments/pullimg.sh
```

Then we need to manually build the image for Kafka Connect, this script will build and install the image with a connector `mongo-kafka-connect-1.11.2-all.jar`:

```
$ ./deployments/build_kafka_connect.sh
```

There are many other kind of connectors from many different vendors (Debezium, Confluent,...), you can use and test with them.

## Install MongoDB

Install the source instance of MongoDB replicaset.
Within the `values.yaml` file of MongoDB helm chart, I already set these configurations.

```
global.imageRegistry: "localhost:5001"
replicaSetName: rs0
auth.rootUser: root
auth.rootPassword: root
auth.usernames: ["user1"]
auth.passwords: ["password1"]
auth.databases: ["stg"]
```

Initially the helm chart will create a database `stg` with it's user is `user1`.

Then run this command to install `mongodb` replicaset:

```
$ helm install mongodb deployments/helm/mongodb
```

As the result, the first MongoDB replicaset instance will have these addresses:

```
MongoDB&reg; can be accessed on the following DNS name(s) and ports from within your cluster:
    mongodb-0.mongodb-headless.default.svc.cluster.local:27017
    mongodb-1.mongodb-headless.default.svc.cluster.local:27017
```

Next, lets install the second MongoDB replicaset instance, with will be the sink DB.

```
$ helm install mongodb2 deployments/helm/mongodb
```

Both replicaset will have the same name `rs0`, but with different addresses.

```
MongoDB&reg; can be accessed on the following DNS name(s) and ports from within your cluster:
    mongodb2-0.mongodb2-headless.default.svc.cluster.local:27017
    mongodb2-1.mongodb2-headless.default.svc.cluster.local:27017
```

When both `mongodb` and `mongodb2` has finished boot up, run this command to check for pods and services:

```
$ kubectl get pods -n default
NAME                 READY   STATUS    RESTARTS   AGE
mongodb-0            1/1     Running   0          5m45s
mongodb-1            1/1     Running   0          5m29s
mongodb-arbiter-0    1/1     Running   0          5m45s
mongodb2-0           1/1     Running   0          38s
mongodb2-1           1/1     Running   0          23s
mongodb2-arbiter-0   1/1     Running   0          38s

$ kubectl get svc -n default
NAME                        TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)     AGE
kubernetes                  ClusterIP   10.96.0.1    <none>        443/TCP     7m44s
mongodb-arbiter-headless    ClusterIP   None         <none>        27017/TCP   6m54s
mongodb-headless            ClusterIP   None         <none>        27017/TCP   6m54s
mongodb2-arbiter-headless   ClusterIP   None         <none>        27017/TCP   107s
mongodb2-headless           ClusterIP   None         <none>        27017/TCP   107s
```

## Install Kafka cluster

We'll use Kafka Kraft with these settings for `values.yaml`:

```
global.imageRegistry: "localhost:5001"
listeners.client.protocol: PLAINTEXT
extraDeploy:
  - |
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: {{ include "common.names.fullname" . }}-connect
      labels: {{- include "common.labels.standard" ( dict "customLabels" .Values.commonLabels "context" $ ) | nindent 4 }}
        app.kubernetes.io/component: connector
    spec:
      replicas: 1
      selector:
        matchLabels: {{- include "common.labels.matchLabels" ( dict "customLabels" .Values.commonLabels "context" $ ) | nindent 6 }}
          app.kubernetes.io/component: connector
      template:
        metadata:
          labels: {{- include "common.labels.standard" ( dict "customLabels" .Values.commonLabels "context" $ ) | nindent 8 }}
            app.kubernetes.io/component: connector
        spec:
          containers:
            - name: connect
              image: localhost:5001/bitnami/kafka-connect:latest
              imagePullPolicy: Always
              ports:
                - name: connector
                  containerPort: 8083
              volumeMounts:
                - name: configuration
                  mountPath: /bitnami/kafka/config
          volumes:
            - name: configuration
              configMap:
                name: {{ include "common.names.fullname" . }}-connect
  - |
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: {{ include "common.names.fullname" . }}-connect
      labels: {{- include "common.labels.standard" ( dict "customLabels" .Values.commonLabels "context" $ ) | nindent 4 }}
        app.kubernetes.io/component: connector
    data:
      connect-standalone.properties: |-
        bootstrap.servers = {{ include "common.names.fullname" . }}-controller-0.{{ include "common.names.fullname" . }}-controller-headless.{{ include "common.names.namespace" . }}.svc.{{ .Values.clusterDomain }}:{{ .Values.service.ports.client }}
        key.converter = org.apache.kafka.connect.json.JsonConverter
        value.converter = org.apache.kafka.connect.json.JsonConverter
        offset.storage.file.filename=/tmp/connect.offsets
        plugin.path=/opt/bitnami/kafka/libs
        plugin.discovery=service_load
        ...
  - |
    apiVersion: v1
    kind: Service
    metadata:
      name: {{ include "common.names.fullname" . }}-connect
      labels: {{- include "common.labels.standard" ( dict "customLabels" .Values.commonLabels "context" $ ) | nindent 4 }}
        app.kubernetes.io/component: connector
    spec:
      ports:
        - protocol: TCP
          port: 8083
          targetPort: connector
      selector: {{- include "common.labels.matchLabels" ( dict "customLabels" .Values.commonLabels "context" $ ) | nindent 4 }}
        app.kubernetes.io/component: connector
```

This setting will enable helm to install Kafka cluster, along with Kafka Connect service, using the image that we built in the previous step.

It will also configure Kafka Connect to look at path `/opt/bitnami/kafka/libs` for plugins to load.

Now we can use these DNS addresses to interact with Kafka cluster

```
# controller
kafka.default.svc.cluster.local:9092

# brokers
kafka-controller-0.kafka-controller-headless.default.svc.cluster.local:9092
kafka-controller-1.kafka-controller-headless.default.svc.cluster.local:9092
kafka-controller-2.kafka-controller-headless.default.svc.cluster.local:9092
```

Then check for pods and services of Kafka:

```
$ kubectl get pods -n default
NAME                             READY   STATUS    RESTARTS   AGE
kafka-connect-5c77c46494-4w8w7   1/1     Running   0          48s
kafka-controller-0               1/1     Running   0          48s
kafka-controller-1               1/1     Running   0          48s
kafka-controller-2               1/1     Running   0          48s

$ kubectl get svc -n default
NAME                        TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
kafka                       ClusterIP   10.96.43.109    <none>        9092/TCP                     2m37s
kafka-connect               ClusterIP   10.96.210.147   <none>        8083/TCP                     2m37s
kafka-controller-headless   ClusterIP   None            <none>        9094/TCP,9092/TCP,9093/TCP   2m37s
```

### Testing Kafka cluster

You can create a kafka client pod, and connect to Kafka cluster to check for topics, consumer, etc...

This command will create a kafka client pod and `ssh` to that pod

```
./deployments/testkafka.sh
```

Navigate to the `/opt/bitnami/kafka/bin` directory and list out all current topics (at this step there should be no topic):

```
$ kafka-topics.sh --list --bootstrap-server kafka-controller-0.kafka-controller-headless.default.svc.cluster.local:9092
```

You can checkout other `.sh` tool to produce or consume message in this `bin` directory.

## Expose services

At this step, we will expose MongoDB and Kafka Connect to outside of the Kubernetes and access them.

```
$ ./deployments/port_forward.sh
```

MongoDB source cluster will be accessible at `localhost:27017`

MongoDB sink cluster will be accessible at `localhost:27018`

Kafka Connect REST API will be accessible at `localhost:8083`

## Setup Source & Sink connectors

### Source connector

Here is source connector config

```
{
  "name": "mongodb-source",
  "config": {
    "connector.class": "com.mongodb.kafka.connect.MongoSourceConnector",
    "topic.prefix": "mongodb",
    "connection.uri": "mongodb://root:root@mongodb-0.mongodb-headless.default.svc.cluster.local:27017,mongodb-1.mongodb-headless.default.svc.cluster.local:27017/?replicaSet=rs0"
  }
}

```

To install Source connector, run this command

```
$ curl -X POST -H "Content-Type: application/json" -d @create_source_connector.json localhost:8083/connectors
```

You should receive a response from server that the request is successful

```
{"name":"mongodb-source","config":{"connector.class":"com.mongodb.kafka.connect.MongoSourceConnector","topic.prefix":"mongodb","connection.uri":"mongodb://root:root@mongodb-0.mongodb-headless.default.svc.cluster.local:27017,mongodb-1.mongodb-headless.default.svc.cluster.local:27017/?replicaSet=rs0","name":"mongodb-source"},"tasks":[{"connector":"mongodb-source","task":0}],"type":"source"}
```

### Sink connector

Here is sink connector config

```
{
    "name": "mongodb-sink",
    "config": {
        "connector.class": "com.mongodb.kafka.connect.MongoSinkConnector",
        "topics": "mongodb.stg.blocks",
        "task.max": "1",
        "connection.uri": "mongodb://root:root@mongodb2-0.mongodb2-headless.default.svc.cluster.local:27017,mongodb2-1.mongodb2-headless.default.svc.cluster.local:27017/?replicaSet=rs0",
        "database": "stg",
        "collection": "blocks",
        "change.data.capture.handler":"com.mongodb.kafka.connect.sink.cdc.mongodb.ChangeStreamHandler"
    }
}
```

In this config, we're using `ChangeStreamHandler` which is the default Change Stream handler to handle the raw messages from Kafka Topic.

To install Sink connector, run this command

```
$ curl -X POST -H "Content-Type: application/json" -d @create_sink_connector.json localhost:8083/connectors
```

Response should be like this

```
{"name":"mongodb-sink","config":{"connector.class":"com.mongodb.kafka.connect.MongoSinkConnector","topics":"mongodb.stg.blocks","task.max":"1","connection.uri":"mongodb://root:root@mongodb2-0.mongodb2-headless.default.svc.cluster.local:27017,mongodb2-1.mongodb2-headless.default.svc.cluster.local:27017/?replicaSet=rs0","database":"stg","collection":"blocks","change.data.capture.handler":"com.mongodb.kafka.connect.sink.cdc.mongodb.ChangeStreamHandler","name":"mongodb-sink"},"tasks":[{"connector":"mongodb-sink","task":0}],"type":"sink"}
```

You can also use Kafka Client to check for current topics, and the result should be like this

```
mongodb.stg.blocks
```

As `blocks` is the expected collection in the `stg` database that the connectors will capture data change from.

## Test data sync

You can use any tool to connect to MongoDB source cluster, and create an item into `blocks` collection

```
{
    "block_int": 123,
    "transactions": [

    ]
}
```

Then connect to MongoDB sink cluster and see that the item has been synced and insert to `blocks` collection.
