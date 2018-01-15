
#### Getting started

Here is the architecture that we will put in place:

![](https://cdn-images-1.medium.com/max/800/1*5_N3RvDOnaQf5MNusI0yHA.png)

To deploy our CI Architecture, we will use the Kubernetes Architecture. To be
able to understand the rest, you must know these principles:

* [Pod](https://kubernetes.io/docs/concepts/workloads/pods/pod-overview/)
* [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
* [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
* [Google Cloud persistent disk](https://cloud.google.com/persistent-disk/?hl=fr)

### The TeamCity Server container

#### TeamCity server: Docker image

Create a new TeamCity server docker image that includes last PostgreSQL driver

* Download the last PostgreSQL jar from [here](https://jdbc.postgresql.org/)
* Create a new DockerFile:

    FROM jetbrains/teamcity-server
    COPY postgresql-xx.x.x.jar  /data/teamcity_server/datadir/lib/jdbc/

Open a GKE Terminal and build your image:

    docker build -t gcr.io/<YOUR-PROJECT-ID>/teamcity-server:1.0.4 .

After then, push it inside you repository:

    gcloud docker -- push gcr.io/<YOUR-PROJECT-ID>/teamcity-server:1.0.4

#### TeamCity agent: Docker image

Our TeamCity agent must be able to build, publish and deploy docker container.
In order to do that, it need to be authenticated as owner on the Gcloud
plateform. One solution is to create a service-accounts with the owner role and
use it inside the container.

We’ll use the following code to do that:

    #!/bin/bash
    version=1.0.6
    projectId=xxxx-xx
    alreadyExists=$(gcloud iam service-accounts list | grep agent-ci@$projectId.iam.gserviceaccount.com | wc -l)
    if [ $alreadyExists -eq 0 ]
    then
      gcloud iam service-accounts create agent-ci --display-name "My CI service account"

      gcloud projects add-iam-policy-binding $projectId  --member serviceAccount:agent-ci@$projectId.iam.gserviceaccount.com --role roles/owner

      gcloud iam service-accounts keys create  ./cloud-security-key.json --iam-account agent-ci@$projectId.iam.gserviceaccount.com

    fi
    docker build --build-arg projectId=$projectId -t gcr.io/$projectId/teamcity-agent:$version .
    gcloud docker -- push gcr.io/$projectId/teamcity-agent:$version
    kubectl set image deployments/teamcity-agent teamcity-agent=gcr.io/$projectId/teamcity-agent:$version

The code above run the docker build of the following Dockerfile:

Create a new TeamCity agent docker image that includes last PostgreSQL driver:

    FROM  jetbrains/teamcity-agent:latest
    ARG projectId
    COPY cloud-security-key.json  /secrets/
    RUN export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)" ;\
    echo "deb 
     $CLOUD_SDK_REPO main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list ;\
    cat /etc/apt/sources.list.d/google-cloud-sdk.list ;\
    curl 
     | apt-key add - ;\
    apt-get update && apt-get install -y google-cloud-sdk kubectl ;\
    gcloud auth activate-service-account --key-file /secrets/cloud-security-key.json ;\
    gcloud config set project $projectId ;

Configure a new PostgreSQL instance

### Create a Teamcity pod

#### The agent pod

First step, write somewhere your agent configuration. For demo purpose, I choose
to put in on a public GitHub repo, do not do it in production.

We can now write our deployment configuration:

    apiVersion: apps/v1beta1
    kind: Deployment
    metadata:
      name: teamcity-agent
      labels:
        app: teamcity-agent
    spec:
      replicas: 3
      selector:
        matchLabels:
          app: teamcity-agent
      template:
        metadata:
          labels:
            app: teamcity-agent
        spec:
          containers:
          - name: teamcity-agent
            image: gcr.io/<YOUR-PROJECT-ID>/teamcity-agent:1.0.4 
            env:
             - name: SERVER_URL
               value: "
    " 
            volumeMounts:
              - mountPath: /var/run 
                name: docker-sock 
              - mountPath: /data/teamcity_agent/conf
                name: teamcity-agent-config
          volumes:
            - name: teamcity-agent-config
              gitRepo:
                repository: "
    "
                revision: "9cdaa8e8ba0b8367709dabf3a54a0a0eca68228d"
            - name: docker-sock 
              hostPath: 
                  path: /var/run

As you can see, we added several volumes here.

The first one, is the agent config folder.

The second one is the docker sock. It allow to use the host docker cmd inside
our agent. 

#### The server pod

By default, pod have non persistent hard drive. So by restarting your server,
you will lost all your data folder (project configuration etc).

To avoid this, the best solution is to create a persistent disk by using:

    gcloud compute disks create --size 50GB teamcity-server-volume

<br> 

*****

Build

Use the build script in order to build the server image

This script will build and deploy the following Dockerfile:

    FROM jetbrains/teamcity-serverCOPY postgresql-42.1.4.jar  /data/teamcity_server/datadir/lib/jdbc/COPY jonnyzzz.node.zip /data/teamcity_server/datadir/plugins/

<br> 

*****

Deployment

    apiVersion: apps/v1beta1
    kind: Deployment
    metadata:
      name: teamcity-server
      labels:
        app: teamcity-server
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: teamcity-server
      template:
        metadata:
          labels:
            app: teamcity-server
        spec:
          containers:
          - name: teamcity-server
            image: fstn/teamcity-server-postgres
            ports:
            - containerPort: 8111
          - name: cloudsql-proxy
            image: gcr.io/cloudsql-docker/gce-proxy:1.11
            command: ["/cloud_sql_proxy", "--dir=/cloudsql",
                      "-instances= teamcity-postgres=tcp:5432",
                      "-credential_file=/secrets/cloudsql/proxy-sql-secure.json"]
            volumeMounts:
              - name: cloudsql-instance-credentials
                mountPath: /secrets/cloudsql
                readOnly: true
              - name: ssl-certs
                mountPath: /etc/ssl/certs
              - name: cloudsql
                mountPath: /cloudsql            
              - name: data
                mountPath: /data/teamcity_server/datadir
            # [END proxy_container]
          # [START volumes]
          volumes:
            - name: cloudsql-instance-credentials
              secret:
                secretName: cloudsql-instance-credentials
            - name: cloudsql
              emptyDir:
            - name: ssl-certs
              hostPath:
                path: /etc/ssl/certs
            - name: data
              gcePersistentDisk:
                pdName: teamcity-server-volume
                fsType: ext4

### Create a Teamcity service

In order to access to our TeamCity server, we need to configure a static IP
address :

    kind: Service
    apiVersion: v1
    metadata:
      name: teamcity-server-service
    spec:
      type: LoadBalancer
      selector:
        app: teamcity-server
      ports:
      - protocol: TCP
        port: 80
        targetPort: 8111

### Database configuration

In order to get your database proxy user and password, you need to open the
secrets doing this:

    kubectl get secret cloudsql-db-credentials -o yaml

### Install a build agent

<br> 

![](https://cdn-images-1.medium.com/max/800/1*Eu-o7ozH0mjt6kjJAnbRcg.png)

<br> 

![](https://cdn-images-1.medium.com/max/800/1*pbeMpfkNQgG0QcGXfYQLvg.png)

<br> 

<br> 

<br> 

### Bonus

<br> 

delete a replicat

    kubectl delete rc peter-admin

create a replicat

    kubectl create -f ci-peter-admin.yaml

Create a loadbalancer

<br> 

Create a static IP address

    gcloud compute addresses create peter-bot-ip --global

<br> 

### Teamcity nodeJS

<br> 

install NodeJS on agent

<br> 

[https://github.com/jonnyzzz/TeamCity.Node](https://github.com/jonnyzzz/TeamCity.Node).

<br> 

Deploy a web project 

<br> 

<br> 
