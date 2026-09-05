# Ansible k8s for Ubuntu on Raspberry PI nodes

This set of playbooks is built out to pre-configure my worker and master nodes for a k8s cluster and represents my first forray into Ansible.

I'm sure there's plenty of improvements that could be made here but for now this provides me with a basic level of automation and control over the nodes.

You can find more details on what I'm working on over at [my blog](https://techhub.jhbutler.net/). 

## Kube-apiserver service-account audiences

The active Kubernetes playbook manages the kubeadm-generated static-pod manifest
on the control-plane node. It preserves the service-account issuer
`https://kubernetes.default.svc.cluster.local` and configures both accepted API
audiences: `kubernetes.default.svc` and
`https://kubernetes.default.svc.cluster.local`.

Apply only to the control-plane group during an approved maintenance window:

```sh
uv run ansible-playbook -i cluster.yaml playbooks/install_upgrade-kubernetes.yaml \
  --limit masters --tags kube-apiserver-audience
```

Changing the static-pod manifest causes kubelet to recreate kube-apiserver
automatically; expect a brief control-plane/API interruption. No separate restart
command is normally required. Verify after recovery with standard `kubectl`:

```sh
kubectl get --raw=/readyz
kubectl --namespace hermes-agent auth can-i \
  --as=system:serviceaccount:hermes-agent:hermes-agent get pods
kubectl --namespace hermes-agent get pods
```
