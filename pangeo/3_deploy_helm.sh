#!/bin/bash

set -e

kubectl config set-context $(kubectl config current-context) --namespace ${NAMESPACE:-pangeo}
helm repo add pangeo https://pangeo-data.github.io/helm-chart/
helm repo update

helm upgrade --install pangeo pangeo/pangeo --namespace=pangeo \
   -f secret_config.yaml -f jupyter_config.yaml --version=v0.1.1-93765e6 

#kubectl annotate svc proxy-public service.beta.kubernetes.io/openstack-internal-load-balancer="true" --overwrite
