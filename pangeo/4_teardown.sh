helm delete pangeo --purge
helm reset --force
kubectl delete -n kube-system svc/tiller-deploy deploy/tiller-deploy
rm -rf ~/.helm
