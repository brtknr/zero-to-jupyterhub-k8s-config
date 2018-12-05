Setup:

    kubectl patch deployment tiller-deploy --namespace=kube-system --type=json --patch='[{"op": "add", "path": "/spec/template/spec/containers/0/command", "value": ["/tiller", "--listen=localhost:44134"]}]'
    kubectl --namespace kube-system create serviceaccount tiller
    kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
    helm init --service-account tiller --client-only

Spin up jupyterhub:

    helm upgrade jhub jupyterhub/jupyterhub --version=v0.7 --namespace=jhub -f config.yaml  --debug --install

Delete jupyterhub:

    helm delete --purge jhub
