#!/bin/sh

. /etc/sysconfig/heat-params

set -x


echo "Waiting for Kubernetes API..."
until  [ "ok" = "$(curl --silent http://127.0.0.1:8080/healthz)" ]
do
    sleep 5
done

node_name=$(cut -d"." -f1 /etc/hostname)
until kubectl get no "${node_name}"
do
  sleep 5
done
kubectl label node "${node_name}" node-role.kubernetes.io/master=""

# NOTE(flwang): Let's keep the same addons yaml file on all masters,
# but if it's not the primary/bootstrapping master, don't try to
# create those resources to avoid race condition issue until the
# kubectl issue https://github.com/kubernetes/kubernetes/issues/44165
# fixed.

if [ "$MASTER_INDEX" != "0" ]; then
    exit 0
fi

cat <<EOF | kubectl apply --validate=false -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF

cat <<EOF | kubectl apply --validate=false -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF

# Create an admin user and give it the cluster role.
ADMIN_RBAC=/srv/magnum/kubernetes/kubernetes-admin-rbac.yaml

[ -f ${ADMIN_RBAC} ] || {
    echo "Writing File: $ADMIN_RBAC"
    mkdir -p $(dirname ${ADMIN_RBAC})
    cat << EOF > ${ADMIN_RBAC}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin
  namespace: kube-system
EOF
}

kubectl apply --validate=false -f ${ADMIN_RBAC}

if [ -z "${TRUST_ID}" ]; then
   exit 0
fi

#TODO: add heat variables for master count to determine leaderelect true/False ?
# Add label for the openstack-cloud-controller-manager occm_tag
# using docker.io/k8scloudprovider/openstack-cloud-controller-manager:v0.2.0

occm_prefix="${CONTAINER_INFRA_PREFIX:-docker.io/k8scloudprovider/}"

OCCM=/srv/magnum/kubernetes/openstack-cloud-controller-manager.yaml
[ -f ${OCCM} ] || {
    echo "Writing File: ${OCCM}"
    mkdir -p $(dirname ${OCCM})
    cat << EOF > ${OCCM}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: openstack-cloud-controller-manager
  namespace: kube-system
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: system:openstack-cloud-controller-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: openstack-cloud-controller-manager
  namespace: kube-system
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    k8s-app: openstack-cloud-controller-manager
  name: openstack-cloud-controller-manager
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: openstack-cloud-controller-manager
  template:
    metadata:
      labels:
        k8s-app: openstack-cloud-controller-manager
    spec:
      hostNetwork: true
      serviceAccountName: openstack-cloud-controller-manager
      containers:
      - name: openstack-cloud-controller-manager
        image: ${occm_prefix}openstack-cloud-controller-manager:v0.3.0
        command:
        - /bin/openstack-cloud-controller-manager
        - --v=2
        - --cloud-config=/etc/kubernetes/kube_openstack_config
        - --cloud-provider=openstack
        - --cluster-name=${CLUSTER_UUID}
        - --use-service-account-credentials=true
        - --bind-address=127.0.0.1
        - --kubeconfig=/etc/kubernetes/kubelet-config.yaml
        volumeMounts:
        - name: cloudconfig
          mountPath: /etc/kubernetes
          readOnly: true
      volumes:
      - name: cloudconfig
        hostPath:
          path: /etc/kubernetes
      tolerations:
      # this is required so CCM can bootstrap itself
      - key: node.cloudprovider.kubernetes.io/uninitialized
        value: "true"
        effect: NoSchedule
      # this is to have the daemonset runnable on master nodes
      # the taint may vary depending on your cluster setup
      - key: dedicated
        value: master
        effect: NoSchedule
      - key: CriticalAddonsOnly
        value: "True"
        effect: NoSchedule
      # this is to restrict CCM to only run on master nodes
      # the node selector may vary depending on your cluster setup
      nodeSelector:
        node-role.kubernetes.io/master: ""
EOF
}

kubectl replace -f ${OCCM} --force

