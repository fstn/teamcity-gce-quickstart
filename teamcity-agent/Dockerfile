FROM  jetbrains/teamcity-agent:latest
ARG projectId
COPY cloud-security-key.json  /secrets/
RUN export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)" ;\
echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list ;\
cat /etc/apt/sources.list.d/google-cloud-sdk.list ;\
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - ;\
apt-get update && apt-get install -y google-cloud-sdk kubectl ;\
gcloud auth activate-service-account --key-file /secrets/cloud-security-key.json ;\
gcloud config set project $projectId ;
