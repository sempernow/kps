# [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack#kube-prometheus-stack) (KPS) 

<!--
<span style="display: flex;height: 33px;width: 33px">
    <img src="grafana-logo.png" title="Grafana" >
    &nbsp;&nbsp;
    <img src="prometheus-logo.png" title="Prometheus"> 
</span> 
-->

KPS is a collection of Kubernetes manifests, [Grafana](https://grafana.com) (<img src="grafana-logo.png" style="height:1em;width:1em;">) dashboards, and [Prometheus](https://prometheus.io/ "prometheus.io") (<img src="prometheus-logo.png" style="height:1em;width:1em;">) [rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/ "prometheus.io/docs") combined with documentation and scripts to provide easy to operate *end-to-end Kubernetes cluster monitoring* with Prometheus using the [**Prometheus Operator**](https://github.com/prometheus-operator/prometheus-operator).

## [Prometheus Community](https://github.com/prometheus-community "github.com/prometheus-community")

- OCI Artifact: `oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack`
    - [Helm OCI-based repositories](https://helm.sh/docs/topics/registries/)
- Helm Repository: https://prometheus-community.github.io/helm-charts 

## Install by Helm 

KP**Stack** management functions ([`stack.sh`](stack.sh)) 
are executed by make recipes. 


```bash
# List recipes
make
```

## KPS minimal configuration  ([MD](kps.minimal.md)|[HTML](kps.minimal.html))

## Grafana LDAP Integration ([`values.grafana-ldap.yaml`](values.grafana-ldap.yaml))

### TL;DR

Success! 

User `u2` authenticated against AD via LDAP at Grafana `/login` page.

### Work

At "Windows Server 2019", 
we created "User" "`svc-ldap-grafana`" in "OU" at "`OU1/ServiceAccounts`", at GUI of ADUAC.


Right click on that **User**  > "**All Tasks**" > "**Name Mappings**"   
launches window "**Security Identity Mapping**"   
having field "**Mapped user account**" having value:   

```ini
lime.lan/OU1/ServiceAccounts/svc-ldap-grafana
```

How to **map that to Grafana's LDAP parameters**:

```ini
lime.lan / OU1 / ServiceAccounts / svc-ldap-grafana
  ↓          ↓         ↓                  ↓
DC=lime,  OU=OU1,  OU=ServiceAccounts,  CN=svc-ldap-grafana
DC=lan
```

Assembled in LDAP order (reverse of ADUC path), the **`bind_dn` setting** is:

```ini
CN=svc-ldap-grafana,OU=ServiceAccounts,OU=OU1,DC=lime,DC=lan
```

Test/Confirm using `ldapsearch` :

```bash
sudo apt install -y ldap-utils

ldapsearch -H ldaps://dc1.lime.lan:636 \
    -D "CN=svc-ldap-grafana,OU=ServiceAccounts,OU=OU1,DC=lime,DC=lan" \
    -w "$svc_ldap_grafana_password" \
    -b "DC=lime,DC=lan" \
    "(sAMAccountName=svc-ldap-grafana)" dn
```
- Function `ldapSearch` added at [`stack.sh`](stack.sh)
    - See recipe: "`make ldaptest`"

Response confirms we have the proper `bind_dn` settings:

```ini
# extended LDIF
#
# LDAPv3
# base <DC=lime,DC=lan> with scope subtree
# filter: (sAMAccountName=svc-ldap-grafana)
# requesting: dn
#

# svc-ldap-grafana, ServiceAccounts, OU1, lime.lan
dn: CN=svc-ldap-grafana,OU=ServiceAccounts,OU=OU1,DC=lime,DC=lan

# search reference
ref: ldaps://ForestDnsZones.lime.lan/DC=ForestDnsZones,DC=lime,DC=lan

# search reference
ref: ldaps://DomainDnsZones.lime.lan/DC=DomainDnsZones,DC=lime,DC=lan

# search reference
ref: ldaps://lime.lan/CN=Configuration,DC=lime,DC=lan

# search result
search: 2
result: 0 Success

# numResponses: 5
# numEntries: 1
# numReferences: 3
```
- The "`result: 0 Success`" and exact DN match confirm our `bind_dn` string is proper.


```bash
☩ k exec kps-grafana-56769cdddb-fng92 -- cat /etc/grafana/ldap.toml
```
```toml
[[servers]]
host = "dc1.lime.lan"
port = 636
use_ssl = true
start_tls = false
ssl_skip_verify = false
root_ca_cert = "/etc/grafana/certs/ca.pem"

bind_dn = "CN=svc-ldap-grafana,OU=ServiceAccounts,OU=OU1,DC=lime,DC=lan"
bind_password = "SVC_LDAP_GRAFANA_PASSWORD"

search_filter = "(sAMAccountName=%s)"
search_base_dns = ["DC=lime,DC=lan"]

[servers.attributes]
name = "givenName"
surname = "sn"
username = "sAMAccountName"
member_of = "memberOf"
email = "mail"

[[servers.group_mappings]]
group_dn = "*"
org_role = "Viewer"
```
