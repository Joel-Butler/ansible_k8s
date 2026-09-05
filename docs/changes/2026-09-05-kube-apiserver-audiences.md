# Kubernetes API-server audience fix — 2026-09-05

## Root cause

Hermes Agent presented a valid, unexpired projected ServiceAccount token, and its
RBAC authorization was correct, but the kube-apiserver rejected the token with
HTTP 401. The token audience was `kubernetes.default.svc`, while the configured
service-account issuer was `https://kubernetes.default.svc.cluster.local` and no
explicit `--api-audiences` was configured. The issuer/audience configuration did
not accept the audience used by Hermes.

## Change

`playbooks/vars/k8s.yaml` now defines `jb_k8s_api_audiences` with:

- `kubernetes.default.svc`
- `https://kubernetes.default.svc.cluster.local`

The active `playbooks/install_upgrade-kubernetes.yaml` updates the kubeadm static
pod manifest `/etc/kubernetes/manifests/kube-apiserver.yaml` idempotently,
preserving:

```text
--service-account-issuer=https://kubernetes.default.svc.cluster.local
```

and ensuring exactly one:

```text
--api-audiences=kubernetes.default.svc,https://kubernetes.default.svc.cluster.local
```

No Hermes RBAC, token lifetimes, roles, permissions, secrets, or token values were
changed.

## Validation

The playbook was syntax-checked and linted. The rendered argument from the Ansible
variable was inspected to confirm both audience values; the manifest task asserts
the unchanged issuer, the exact audience list, and a single audience argument when
run on the control-plane host. No scanner configuration is committed in the
repository; the available `gitleaks` scanner ran against the repository and found
no leaks.

No live cluster write was performed by this change or its validation.
