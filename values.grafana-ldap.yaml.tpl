## https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/ldap/
grafana:

  extraConfigmapMounts:
    ## See ldap.config: root_ca_cert
    ## kubectl -n kps create cm grafana-ldap-certs --from-file=ca.pem=/path/to/ca.pem
    ## kubectl -n kps create cm grafana-ldap-certs --from-file=ca.pem=/path/to/ca.pem
    - name: ldap-certs
      configMap: grafana-ldap-certs
      mountPath: /etc/grafana/certs
      readOnly: true

  grafana.ini:
    log:
      mode: console
      filters: "ldap:debug"

  ## LDAP Authentication can be enabled with the following values on grafana.ini
    auth.ldap:
      enabled: true
      config_file: /etc/grafana/ldap.toml
      allow_sign_up: true

  ## Grafana's LDAP configuration
  ## Templated by the template in _helpers.tpl
  ## NOTE: To enable the grafana.ini must be configured with auth.ldap.enabled
  ## ref: http://docs.grafana.org/installation/configuration/#auth-ldap
  ## ref: http://docs.grafana.org/installation/ldap/#configuration
  ldap:
    enabled: true
    config: |-
      [[servers]]
      host = "LDAP_HOST"
      port = 636
      use_ssl = true
      start_tls = false
      ssl_skip_verify = false
      root_ca_cert = "/etc/grafana/certs/ca.pem"

      bind_dn = "LDAP_BIND_DN"
      bind_password = "SVC_LDAP_GRAFANA_PASSWORD"

      search_filter = "(sAMAccountName=%s)"
      search_base_dns = ["LDAP_SEARCH_BASE"]

      [servers.attributes]
      name = "givenName"
      surname = "sn"
      username = "sAMAccountName"
      member_of = "memberOf"
      email = "mail"

      [[servers.group_mappings]]
      group_dn = "*"
      org_role = "Viewer"
