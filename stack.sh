#!/usr/bin/env bash
#######################################################
# kube-prometheus-stack by Helm method
# 
# KPS GitHub project:
# https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
#######################################################
installHelm(){
    ver=${1:-v3.17.3}
    ver=${1:-v4.1.1}
    what=linux-amd64
    url=https://get.helm.sh/helm-${ver}-$what.tar.gz
    type -t helm > /dev/null 2>&1 &&
        helm version |grep $VER > /dev/null 2>&1 || {
            echo '  INSTALLing helm'
            curl -sSfL $url |tar -xzf - &&
                sudo install $what/helm /usr/local/bin/ &&
                    rm -rf $what &&
                        echo ok || echo ERR : $?
        }
}
installHelm4Latest(){
    type -t helm > /dev/null 2>&1 ||
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 |
            bash
}

RELEASE="${KPS_RELEASE:-kps}"
NAMESPACE="${KPS_NAMESPACE:-kps}"

# Chart
VER=82.4.0
REPO=prometheus-community
CHART=kube-prometheus-stack
ARCHIVE=${CHART}-$VER.tgz

pull(){
    ls ${CHART}*.tgz 2>/dev/null && return 0
    helm repo add $REPO https://$REPO.github.io/helm-charts --force-update
    helm pull $REPO/$CHART --version $VER
    ls ${CHART}*.tgz 2>/dev/null || return 1
}
template(){
    helm template $RELEASE $REPO/$CHART $OPTS |tee helm.template.yaml
}
imagesExtract(){
    template
    echo -e '\n=== Chart images'
    grep image: helm.template.yaml |
        sort -u |
        sed 's/^[[:space:]]*//g' |
        cut -d' ' -f2 |sed 's/"//g' |
        tee kps.images
}
valuesExtract(){
    template >/dev/null
    echo -e '\n=== (Sub)Chart values file(s)'
    tar -tvf $ARCHIVE  |
        grep values.yaml |
        awk '{print $6}' |
        xargs -n1 tar -xaf $ARCHIVE &&
            find $CHART -type f -exec /bin/bash -c '
                fname=${1%/*};fname=${fname##*/};echo $fname;mv $1 values.$fname.yaml
            ' _ {} \; && rm -rf $CHART
    find . -type f -iname 'values.*.yaml'
}
ldapCA(){
    ## Create ConfigMap in target namespace having CA (ca.pem) of LDAPS (LDAP over TLS) server
    grep "\b$NAMESPACE\b" <(kubectl get ns --no-headers) ||
        kubectl create ns $NAMESPACE

    kubectl -n $NAMESPACE create cm grafana-ldap-certs --from-file=ca.pem=$LDAP_ROOT_CA
}
ldapSvcPassword(){
    secure=svc-ldap-grafana-password.age
    [[ -f $secure ]] || return 1
    type -t agede >/dev/null 2>&1 &&
        agede $secure ||
            return 2
}
export -f ldapSvcPassword
ldapSearch(){
    type -t ldapsearch >/dev/null 2>&1 ||
        sudo apt install -y ldap-utils
    type -t ldapsearch >/dev/null || return 1

    ldapsearch -H ldaps://$LDAP_HOST:636 \
        -D "$LDAP_BIND_DN" \
        -w "$(ldapSvcPassword)" \
        -b "$LDAP_SEARCH_BASE" \
        "(sAMAccountName=svc-ldap-grafana)" dn
}
install(){
    secure=svc-ldap-grafana-password.age
    ldap_values=values.grafana-ldap.yaml
    values="-f values.minimal.yaml -f values.ingress.yaml -f $ldap_values"
    opts="-n $NAMESPACE --create-namespace --version $VER" 

    [[ -f $secure ]] || return 1
    unset pass; type -t agede >/dev/null 2>&1 && pass="$(agede $secure)" 
    [[ $pass ]] || return 2

    cat $ldap_values.tpl |
        sed "s/LDAP_HOST/$LDAP_HOST/g" |
        sed "s/SVC_LDAP_GRAFANA_PASSWORD/$(ldapSvcPassword)/g" |
        sed "s/LDAP_BIND_DN/$LDAP_BIND_DN/g" |
        sed "s/LDAP_SEARCH_BASE/$LDAP_SEARCH_BASE/g" > $ldap_values

    helm show values $REPO/$CHART --version $VER |tee values.yaml &&
        helm template $RELEASE $REPO/$CHART $values $opts |tee helm.template.yaml &&
            helm upgrade $RELEASE $REPO/$CHART --install $values $opts
}
access(){
    ## If (dev/local) cluster lacks Ingress, then port-forward the Services
    _access(){
        ns=${NAMESPACE:-kube-metrics}
        target=${1:-grafana} 
        labels="app.kubernetes.io/name=$target,app.kubernetes.io/instance=$RELEASE"

        echo === ${target^}
        kubectl -n $ns get svc |grep $target >/dev/null 2>&1 || return $?

        case "$target" in
            grafana)        svc=kps-grafana; pmap=3000:80; path=login;;
            prometheus)     svc=kps-kube-prometheus-stack-prometheus; pmap=9090:9090; path=query;;
            alertmanager)   svc=kps-kube-prometheus-stack-alertmanager; pmap=9093:9093; path='';;
            node-exporter)  svc=kps-prometheus-node-exporter; pmap=9100:9100; path='';;
            *) echo "❌  UNKNOWN target: $target" >&2; return 2;;
        esac
        #echo -e "svc: $svc\npmap: $pmap\npath: $path"

        pgrep -f "port-forward .* $svc $pmap" >/dev/null ||
            kubectl -n "$ns" port-forward svc/$svc $pmap >/dev/null 2>&1 &

        sleep 1

        curl -sfIX GET "http://localhost:${pmap%:*}/$path" |head -1 ||
            echo "❌  NOT up on :${pmap%:*}"
    }
    for svc in grafana prometheus alertmanager
    do 
        _access $svc || {
            echo "❌  NO Service having '*${svc}*' in name"
            continue
        }
        [[ $svc == 'grafana' ]] && {
            port=3000
            curl --max-time 3 -sfIX GET http://localhost:$port/login |grep HTTP &&
                echo Origin : http://localhost:$port &&
                pass="$(
                    kubectl -n $NAMESPACE get secrets $RELEASE-grafana -o jsonpath="{.data.admin-password}" \
                    |base64 -d
                )" &&
                echo Login  : admin:$pass ||
                echo FAILed at GET http://localhost:${port}
        }
    done
}
delete(){
    helm delete $RELEASE -n $NAMESPACE
}

[[ $1 ]] || cat "$BASH_SOURCE"

pushd ${BASH_SOURCE%/*} >/dev/null 2>&1 || pushd . >/dev/null || exit 1
"$@" || echo "❌  ERR : $?" >&2
popd >/dev/null
