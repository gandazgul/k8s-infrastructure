# Hostpath Provisioner

This Kustomization deploys the [kubevirt/hostpath-provisioner](https://github.com/kubevirt/hostpath-provisioner) to
provide dynamically provisioned persistent volumes using local host paths on the nodes.

This is particularly useful for single-node clusters or when you want to use the node's local storage for your
workloads. It dynamically creates directories under the configured path (defaulting to `/var/kubernetes`) for each PVC
created that uses the `hostpath` StorageClass.

It is composed of:

- `DaemonSet`: Runs the provisioner on each node.
- `StorageClass`: The default `hostpath` class used by PVCs.
- `rbac.yaml`: Necessary roles and service accounts for the provisioner to operate.
