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
