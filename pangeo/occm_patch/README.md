- Ensure that `/etc/kubernetes/apiserver` and `/etc/kubernetes/controller-manager` do not have `--cloud-config=openstack` arg.
- Ensure that `/etc/kubernetes/kubelet` on worker node is running with `--cloud-config=external` arg.
- Run the shell scripts in this folder on the master node as root user.
