# Prometheus : FIPS/STIG Compliance

The advised approach to scrape `etcd` and `kube-proxy` securely is using **TLS secrets for `etcd`** and **`ServiceMonitor` configurations** for `kube-proxy`. To meet FIPS/STIG standards, ensure Prometheus uses FIPS-validated cryptographic modules (e.g., Go's `crypto/tls` in FIPS mode), enforce strict mTLS, and avoid exposing loopback/control-plane ports to the cluster network.

## 1. Scraping `etcd` (Strict mTLS) 

Because `etcd` secures its metrics using client certificates, you must securely inject these certificates as a Kubernetes `Secret` and map them to your `ServiceMonitor`. [2, 3]  

- Step 1: Extract the required etcd client certificates (usually found on your control plane nodes at `/etc/kubernetes/pki/etcd/`
- Step 2: Create a Kubernetes secret in your Prometheus namespace (`monitoring`): [3]  
    ```bash
    kubectl create secret generic etcd-certs \
    --from-file=ca.crt=/etc/kubernetes/pki/etcd/ca.crt \
    --from-file=healthcheck-client.crt=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
    --from-file=healthcheck-client.key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
    -n monitoring
    ```
- Step 3: Configure `kubeEtcd` in your Helm `values.yaml` to use the TLS secret, and point to the secure `etcd` port (default 2379, or 2381 for `kubeadm`): [6]  
    ```yaml
    kubeEtcd:
      enabled: true
      service:
        enabled: true
        port: 2381
        targetPort: 2381
      serviceMonitor:
        scheme: https
        serverName: etcd-01 # or use a SAN matching your certs
        caFile: /etc/prometheus/secrets/etcd-certs/ca.crt
        certFile: /etc/prometheus/secrets/etcd-certs/healthcheck-client.crt
        keyFile: /etc/prometheus/secrets/etcd-certs/healthcheck-client.key
    ```

## 2. Scraping `kube-proxy`

By default, `kube-proxy` binds only to the local interface (`127.0.0.1`) and listens on port `10249`, which prevents a centralized Prometheus from scraping it directly across the network. [1, 5]  

The advised way to scrape it securely without violating STIG (which forbids exposing sensitive component metrics on non-loopback IPs) is to deploy a **Prometheus Agent or a lightweight `ServiceMonitor` mapping**: [1]  

- **Option A**: **Node-Local Scraping (Most Secure/STIG Compliant)**.   
    Use a lightweight Prometheus instance as an agent (`PrometheusAgent`) running as a DaemonSet on the control-plane and worker nodes. It scrapes `127.0.0.1:10249` locally and pushes data using `remote_write` to the centralized `kube-prometheus-stack`. [1, 7, 8]  
    - **The Modern Operator Way**: `PrometheusAgent` CRD
    The underlying Prometheus Operator (which powers the Helm chart) includes a first-class `PrometheusAgent` Custom Resource Definition (CRD). This resource strips away the heavy parts of Prometheus (storage, rule evaluation, alerting) and is built specifically for passing metrics upstream via `remote_write`.
    The Prometheus Operator features a `PrometheusAgentDaemonSet` feature gate. When enabled, you can instruct the operator to deploy the agent as a `DaemonSet` across your nodes. You then write a small custom manifest targeting the CRD: 
      ```yaml
      apiVersion: ://coreos.com
      kind: PrometheusAgent
      metadata:
        name: node-local-stig-agent
        namespace: monitoring
      spec:
        image: quay.io/prometheus/prometheus:v2.50.0
        # References the Feature Gate behavior to run on all nodes
        podMetadata:
          labels:
            app: node-local-agent
        remoteWrite:
          - url: "http://monitoring.svc"
        # Target local kube-proxy via hostNetworking or a specific Node-level ServiceMonitor

      ```
    - **The Traditional Helm Way**: Deploying a Secondary Sub-Chart
    If you prefer managing everything strictly via Helm, engineers typically deploy a second standalone [Prometheus Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) alongside `kube-prometheus-stack`. [10] 
    Instead of writing a custom `DaemonSet`, you supply a custom values.yaml to the baseline Prometheus chart to strip it down into a lightweight forwarder: [10] 
        * Disable `alertmanager.enabled`, `server.persistentVolume.enabled`, and `pushgateway.enabled`.
        * Enable `extraArgs: { agent: "" }` to trigger native Prometheus Agent mode.
        * Configure `server.deploymentKind: DaemonSet` to force a replica onto every node.
        * Add your `remoteWrite` destination targeting your primary kube-prometheus-stack ingestion endpoint.
- **Option B**: Exposing `kube-proxy` Metrics Remotely.   
    If you must scrape remotely, edit the `kube-proxy` `ConfigMap` in `kube-system` to bind to `0.0.0.0`, but utilize Kubernetes `NetworkPolicies` to ensure only the Prometheus namespace can access port `10249`. Then, apply a `ServiceMonitor`: [9] 
    ```yaml
    apiVersion: ://coreos.com
    kind: ServiceMonitor
    metadata:
      name: kube-proxy
      namespace: monitoring
      labels:
        release: prometheus
    spec:
      selector:
        matchLabels:
          k8s-app: kube-proxy
      endpoints:
      - port: metrics
        interval: 30s
        # Enforce TLS if your kube-proxy metrics endpoint has it enabled

    ```

## FIPS / STIG Considerations 

1. **FIPS Cryptography**: Ensure your Prometheus container images are built using Go with FIPS-compliant cryptographic boundaries (e.g., Red Hat's Go toolset).
2. **Hardened TLS**: Do not use "`InsecureSkipVerify: true`" in your `ServiceMonitor` specs. 
Ensure all TLS configurations strictly use FIPS-approved cipher suites.
3. **Network Policies**: Restrict ingress access strictly to the Prometheus pod. Both `etcd` and `kube-proxy` should explicitly deny all other inbound traffic.

[1] https://www.reddit.com/r/kubernetes/comments/1kym0dn/scraping_control_plane_metrics_in_kubernetes/
[2] https://blog.devops.dev/unlocking-core-kubernetes-metrics-how-to-enable-prometheus-monitoring-for-etcd-bypassing-the-mtls-9c953a69952a
[3] https://www.sysdig.com/blog/monitor-etcd
[4] https://canonical.com/blog/canonical-releases-fips-enabled-kubernetes
[5] https://github.com/siderolabs/talos/discussions/7799
[6] https://fabianlee.org/2022/07/08/prometheus-installing-kube-prometheus-stack-on-a-kubeadm-cluster/
[7] https://medium.com/@vandana.kenche123/new-relic-log-collection-guide-for-coredns-kube-proxy-and-metrics-server-on-eks-fargate-13aa56a1411d
[8] https://www.reddit.com/r/kubernetes/comments/1kym0dn/scraping_control_plane_metrics_in_kubernetes/
[9] https://stackoverflow.com/questions/68409322/prometheus-cannot-scrape-kubernetes-metrics
[10] https://docs.cloud.google.com/stackdriver/docs/managed-prometheus/setup-managed
[11] https://www.squadcast.com/blog/install-prometheus-kubernetes

---

## Notes

These measures must be taken even if the Prometheus stack resides in the same cluster.
In a FIPS/STIG-compliant environment, being in the same cluster does not grant implicit trust. Federal security baselines require strict isolation between the cluster's management layer (control plane) and the tenant layer (user workloads).

Here is exactly why these measures are mandatory within the same cluster:

## 1. Network Boundary Isolation (STIG Requirement)

* **The Risk**: Kubernetes networks are flat by default. If a standard user application in your cluster is compromised, an attacker can scan and access any internal IP or port.
* **The Fix**: Binding kube-proxy to 127.0.0.1 prevents pod-to-pod network attacks entirely. If you change it to 0.0.0.0 to let Prometheus scrape it, you must use a NetworkPolicy to block every other pod in the cluster from hitting that metrics endpoint.

## 2. Defense in Depth & Zero Trust (FIPS/STIG Requirement)

* **The Risk**: Even inside the cluster, sniffing network traffic (man-in-the-middle) between namespaces is technically possible if an attacker gains elevated node privileges or exploits a CNI vulnerability.
* **The Fix**: etcd contains the entire state and secrets of your cluster. Its metrics endpoint can leak sensitive cluster metadata. STIGs require encryption-in-transit for all administrative and operational data. You must use explicit mTLS (certificates) for etcd scraping so the cluster can verify the Prometheus pod is actually authorized to read that data.

## 3. Identity and Access Management (RBAC)

* **The Risk**: Prometheus needs permission to discover endpoints via the Kubernetes API.
* **The Fix**: Even within the same cluster, Prometheus must use a dedicated ServiceAccount bound to a specific ClusterRole that only allows get, list, and watch on services and endpoints. It does not automatically inherit rights to scrape control plane components just by existing in the cluster.




---

<!-- 

… ⋮ ︙ • ● – — ™ ® © ± ° ¹ ² ³ ¼ ½ ¾ ÷ × ₽ € ¥ £ ¢ ¤ ♻ ⚐ ⚑ ✪ ❤  \ufe0f
☢ ☣ ☠ ¦ ¶ § † ‡ ß µ Ø ƒ Δ ☡ ☈ ☧ ☩ ✚ ☨ ☦ ☓ ♰ ♱ ✖  ☘  웃 𝐀𝐏𝐏 🡸 🡺 ➔
ℹ️ ⚠️ ✅ ⌛ 🚀 🚧 🛠️ 🔧 🔍 🧪 👈 ⚡ ❌ 💡 🔒 📊 📈 🧩 📦 🥇 ✨️ 🔚

# Markdown Cheatsheet

[Markdown Cheatsheet](https://github.com/adam-p/markdown-here/wiki/Markdown-Cheatsheet "Wiki @ GitHub")

# README HyperLink

README ([MD](__PATH__/README.md)|[HTML](__PATH__/README.html)) 

# Bookmark

- Target
<a name="foo"></a>

- Reference
[Foo](#foo)

-->
