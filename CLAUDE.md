# ansible_k8s

Ansible playbooks for managing a homelab Kubernetes cluster of Ubuntu Noble nodes — a mix of Raspberry Pi (arm64) and x64 hardware. Single control-plane node, multiple workers.

## What runs on the cluster

Useful as context when reviewing changes that could disrupt workloads:

- **Networking:** Cilium (CNI)
- **Storage:** Rook-Ceph
- **Observability:** Grafana, Prometheus, Loki
- **Backup:** Velero
- **Ingress / external access:** Cloudflared
- **Stateful workloads:** MySQL

Disruptive changes (node reboots, kubelet restarts, network module reloads) should account for these.

## Local environment

Ansible runs from a project-local Python venv at `.venv/` (gitignored), managed as a [uv](https://docs.astral.sh/uv/) project. Dependencies (`ansible`, `ansible-lint`) are declared in [pyproject.toml](pyproject.toml) and pinned in [uv.lock](uv.lock); the Python interpreter is pinned to 3.13 via [.python-version](.python-version). The project is configured with `package = false` under `[tool.uv]` because this repo is tooling, not a Python package.

Install uv first (`brew install uv` on macOS), then bootstrap on a fresh checkout:

```sh
scripts/setup-venv.sh
```

The script just runs `uv sync`, which creates `.venv/`, downloads Python 3.13 if needed, and installs the locked dependency set. Re-running it after a `uv.lock` change reconciles the venv.

**Default invocation pattern (Claude must follow this):** prefix every Ansible command with `uv run` so the call always resolves against the locked project environment, regardless of whether a venv is active in the current shell. Examples:

```sh
uv run ansible-playbook -i cluster.yaml playbooks/<playbook>.yaml
uv run ansible-lint playbooks/<playbook>.yaml
```

Do not emit bare `ansible-playbook` / `ansible-lint` calls, and do not prepend `source .venv/bin/activate &&` — `uv run` is the single, durable form. The human operator may still activate the venv manually for interactive sessions; that is independent of how Claude should invoke these tools.

To upgrade or add dependencies, edit `pyproject.toml` (or `uv add <pkg>` / `uv lock --upgrade-package <pkg>`) and commit the regenerated `uv.lock`.

## Inventory

[cluster.yaml](cluster.yaml) is the **master of record** for the current inventory. The other root-level inventory files ([master-only.yaml](master-only.yaml), [local-only.yaml](local-only.yaml), [Drain-1.yaml](Drain-1.yaml), [Drain-2.yaml](Drain-2.yaml)) are **legacy artifacts** pending cleanup — do not extend them; if a new slice is needed, add a group inside `cluster.yaml`. Rolling-upgrade slicing that used to live in the `Drain-*` inventories is now handled inside playbooks (e.g. `serial:` in [playbooks/apt-upgrade-rolling.yaml](playbooks/apt-upgrade-rolling.yaml)).

`hosts.yaml` and `test-hosts.yaml` are gitignored — they hold the real production inventory and are not committed.

Standard groups in [cluster.yaml](cluster.yaml):

- `masters` — control plane (currently a single node)
- `workers` — all worker nodes
- `pi-masters` / `pi-workers` — arm64 (Raspberry Pi) subset
- `x64-workers` — amd64 subset

Typical invocation:

```sh
uv run ansible-playbook -i cluster.yaml playbooks/<playbook>.yaml
```

## Playbook map

- [playbooks/playbook-master.yaml](playbooks/playbook-master.yaml) — top-level chain for bringing up / upgrading a node: Pi setup → pre-config → Kubernetes install/upgrade.
- [playbooks/install_upgrade-kubernetes.yaml](playbooks/install_upgrade-kubernetes.yaml) — installs/upgrades containerd, kubelet, kubeadm, kubectl. Pins exact k8s versions; manages the apt repo (removes old minor versions, adds the current one). Workers run `kubeadm upgrade node`; the master is intentionally **not** upgraded by this playbook (see below).
- [playbooks/pre-config-all.yaml](playbooks/pre-config-all.yaml) — host hardening, `/etc/hosts`, swap-off, kernel modules (`overlay`, `br_netfilter`), sysctls, base apt packages.
- [playbooks/raspb-pi-setup-noble.yaml](playbooks/raspb-pi-setup-noble.yaml) — Pi-specific kernel cmdline tweaks and disabling cloud-init's `/etc/hosts` rewriting.
- [playbooks/apt-upgrade-rolling.yaml](playbooks/apt-upgrade-rolling.yaml) — rolling `apt dist-upgrade` with reboot-if-required, `serial: 1`. Cordons and drains workers (delegated to the master) before the upgrade and uncordons after the node is `Ready` again; masters are upgraded but not drained.
- [playbooks/manager-setup.yaml](playbooks/manager-setup.yaml) — provisions an admin/manager workstation (kubectl, helm, doppler, go, k9s).
- [playbooks/install_upgrade-admin-clients.yaml](playbooks/install_upgrade-admin-clients.yaml) — keeps `kubectl` current on admin clients.
- [playbooks/helm-repos.yaml](playbooks/helm-repos.yaml) — adds/refreshes Helm repos on `helm-operators` hosts.
- [playbooks/ansible-setup.yaml](playbooks/ansible-setup.yaml) — bootstraps the `ansible` user + SSH key + sudoers on a new node.
- [playbooks/reboot.yaml](playbooks/reboot.yaml) — explicit reboot of a worker subset.
- [playbooks/wireguard.yaml](playbooks/wireguard.yaml) — installs Wireguard locally (config TODO).
- [playbooks/wsl-manager.yaml](playbooks/wsl-manager.yaml), [playbooks/wsl-php-dev.yaml](playbooks/wsl-php-dev.yaml) — dev-environment provisioning.
- [playbooks/playbook.yaml](playbooks/playbook.yaml) — **pure smoke test** (ping workers). Not load-bearing.
- [playbooks/upgrade-kubeadm-master.yaml](playbooks/upgrade-kubeadm-master.yaml) — **draft / not currently used**. Master upgrades are performed manually because there is only one control-plane node and the blast radius of a failed kubeadm upgrade is too high for full automation. Treat this file as a future-expansion placeholder; do not rely on it being current. Note it is pinned to k8s 1.30 and uses an older containerd config approach, both of which would need to be reconciled with [install_upgrade-kubernetes.yaml](playbooks/install_upgrade-kubernetes.yaml) before it could be used.

Templates live in [playbooks/templates/](playbooks/templates/); vars files in [playbooks/vars/](playbooks/vars/).

## Conventions

### Variables and facts

Prefix all custom variables and `set_fact` results with **`jb_`** (e.g. `jb_dpkg_arch`, `jb_module_overlay`) to avoid collisions with role/collection variables. Apply this to any new facts you introduce.

### `become` placement

`become` is set **per task or per task block** — *not* at play level — by deliberate choice, so that privilege escalation is visible at the point it happens.

- If you add a task that needs root, set `become: true` / `become_user: root` on that task.
- If a future playbook is intended to run entirely as a privileged user, document that **at the top of the playbook** and then make any non-root task explicitly `become_user: <other>`. Don't silently rely on play-level inheritance.

### Architecture handling

Mixed arm64/amd64 fleet. `ansible_facts['architecture']` returns `x86_64` / `aarch64`, which doesn't match what apt repos expect. The pattern in [playbooks/install_upgrade-kubernetes.yaml:4-7](playbooks/install_upgrade-kubernetes.yaml#L4-L7) maps these to `amd64` / `arm64` into `jb_dpkg_arch`. Reuse that fact in any new task that needs the dpkg-flavoured arch string.

### Kubernetes package management

The k8s packages (`kubelet`, `kubeadm`, `kubectl`) are held via `dpkg --set-selections hold` so unrelated `apt upgrade` runs don't move them. The install/upgrade playbook unholds them, installs the pinned version, then re-holds via handlers. Preserve this hold/unhold cycle when modifying k8s-package tasks.

When bumping the cluster version, you must update **three** things in [playbooks/install_upgrade-kubernetes.yaml](playbooks/install_upgrade-kubernetes.yaml) in lockstep: add the new minor-version apt repo as `present`, mark the previous one `absent`, and bump the pinned `kubelet=` / `kubeadm=` / `kubectl=` versions.

## Validation

Run `uv run ansible-lint <changed-playbook>` before considering work done. yamllint hints (e.g. `# yamllint disable-line rule:line-length`) appear inline; honour them.

## Out of scope

- **Doppler / secrets.** Doppler is the cluster's secrets manager but is intentionally **not** managed by these playbooks. It is used manually by the operator to inject an SSH private key into the shell before running `ansible-playbook`. The [doppler/](doppler/) directory at the repo root is operator tooling, not playbook input.
- **Cluster workloads.** Helm charts, manifests, and application config live elsewhere; this repo is infrastructure-only (OS, container runtime, kubeadm-managed components).
