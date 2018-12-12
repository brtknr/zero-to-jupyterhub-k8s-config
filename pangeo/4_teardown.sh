helm delete pangeo --purge
helm reset --force --remove-helm-home   
kubectl -n kube-system delete deploy/tiller-deploy svc/tiller-deploy
