# AGENTS.md - Repository Conventions and Gotchas

This file captures high-signal, repository-specific facts that an AI agent might otherwise miss.

## ⚙️ Execution & Environment
*   **Ansible Invocation:** All Ansible commands must be prefixed with `uv run` (e.g., `uv run ansible-playbook...`) to ensure execution in the locked project environment.
*   **Inventory:** `cluster.yaml` is the master of record. Do not modify or extend legacy inventory files (`Drain-*`).
*   **Validation:** Always run `uv run ansible-lint <changed-playbook>` before concluding work.

## 📐 Code Conventions & Architecture
*   **Variable Prefix:** All custom variables and `set_fact` results must be prefixed with `jb_` to prevent collisions.
*   **Privilege Escalation:** `become` must be set *per task or per task block*, never globally at the play level.
*   **Architecture Handling:** Due to mixed arm64/amd64 fleets, map `ansible_facts['architecture']` to `amd64`/`arm64` (e.g., into `jb_dpkg_arch`) for apt repository compatibility.

## 🗃️ Kubernetes Management
*   **K8s Upgrade Cycle:** When bumping the cluster version, you must update three things in `playbooks/install_upgrade-kubernetes.yaml` simultaneously: add the new minor-version apt repo, mark the previous repo absent, and bump the pinned `kubelet=`, `kubeadm=`, and `kubectl=` versions.
*   **Package State:** Maintain the `dpkg --set-selections hold`/unhold cycle for K8s packages during upgrades.
*   **Operational Gotcha (K8s Upgrade):** The `kubeadm upgrade node` task in `playbooks/install_upgrade-kubernetes.yaml` must maintain `ignore_errors: true` because non-zero exit codes are expected without halting the overall upgrade flow.
*   **Future Refactoring (Containerd):** The Containerd configuration in `playbooks/install_upgrade-kubernetes.yaml` uses shell/sed. This step should be refactored to use Jinja2 templates for improved idempotency.

## ⚠️ Out of Scope
*   **Secrets:** This repository does not manage Doppler/secrets; they are injected manually by the operator.
*   **Workloads:** This repo is infrastructure-only (OS, K8s components); Helm charts and application manifests live elsewhere.