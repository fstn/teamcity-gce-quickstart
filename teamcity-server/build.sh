#!/bin/bash

version=1.0.6
projectId=xxxx-xx
docker build -t gcr.io/xxx-xx/teamcity-server:$version .
gcloud docker -- push gcr.io/$projectId/teamcity-server:$version 
