##############################################################################
## Makefile.settings : Environment Variables for Makefile(s)
include Makefile.settings
# … ⋮ ︙ • ● – — ™ ® © ± ° ¹ ² ³ ¼ ½ ¾ ÷ × ₽ € ¥ £ ¢ ¤ ♻ ⚐ ⚑ ✪ ❤  \ufe0f
# ☢ ☣ ☠ ¦ ¶ § † ‡ ß µ Ø ƒ Δ ☡ ☈ ☧ ☩ ✚ ☨ ☦ ☓ ♰ ♱ ✖  ☘  웃 𝐀𝐏𝐏 🡸 🡺 ➔
# ℹ️ ⚠️ ✅ ⌛ 🚀 🚧 🛠️ 🔧 🔍 🧪 👈 ⚡ ❌ 💡 🔒 📊 📈 🧩 📦 🥇 ✨️ 🔚
##############################################################################
## Environment variable rules:
## - Any TRAILING whitespace KILLS its variable value and may break recipes.
## - ESCAPE only that required by the shell (bash).
## - Environment hierarchy:
##   - Makefile environment OVERRIDEs OS environment lest set using `?=`.
##     - `FOO ?= bar` is overridden by parent setting; `export FOO=new`.
##     - `FOO :=`bar` is NOT overridden by parent setting.
##   - Docker YAML `env_file:` OVERRIDEs OS and Makefile environments.
##   - Docker YAML `environment:` OVERRIDEs YAML `env_file:`.
##   - CMD-inline OVERRIDEs ALL REGARDLESS; `make recipeX FOO=new BAR=new2`.


##############################################################################
## Recipes : Meta

menu :
	$(INFO) "🚧  KPS : Kube Prometheus Stack : https://github.com/prometheus-operator/kube-prometheus"
	@echo "pull      : Pull the latest chart archive"
	@echo "template  : Build the K8s manifests from chart templates"
	@echo "images    : Extract all images of all (sub)charts to file"
	@echo "values    : Extract all values files of all (sub)charts to files"
	@echo "ldapca    : Create ConfigMap of LDAP server CA certificate"
	@echo "ldaptest  : Test bind_dn using ldapsearch"
	@echo "install   : Install by Helm chart"
	@echo "upgrade   : Upgrade the running release"
	@echo "admin     : Get 'admin' user password"
	@echo "access    : Forward Grafana port for local access (Remove: pkill kubectl)"
	@echo "delete    : Delete the running release"
	$(INFO) "🛠️  Maintenance : Meta"
	@echo "helm         : Install helm CLI"
	@echo "env          : Print the make environment"
	@echo "mode         : Fix folder and file modes of this project"
	@echo "eol          : Fix line endings : Convert all CRLF to LF"
	@echo "html         : Process all markdown (MD) to HTML"
	@echo "commit       : Commit and push this source"
	@echo "bundle       : Create ${PRJ_ROOT}.bundle"

env :
	$(INFO) 'Environment'
	@echo "PWD=${PRJ_ROOT}"
	@echo
	@env |grep KPS_ |sort
	@echo
	@env |grep LDAP_ |sort

eol :
	find . -type f ! -path '*/.git/*' -exec dos2unix {} \+
mode :
	find . -type d ! -path './.git/*' -exec chmod 755 "{}" \;
	find . -type f ! -path './.git/*' -exec chmod 640 "{}" \;
#	find . -type f ! -path './.git/*' -iname '*.sh' -exec chmod 755 "{}" \;
tree :
	tree -d |tee tree-d
html :
	find . -type f ! -path './.git/*' -name '*.md' -exec md2html.exe "{}" \;
commit push : html mode
	gc && git push && gl && gs
bundle :
	git bundle create ${PRJ_ROOT}.bundle --all

##############################################################################
## Recipes : Cluster

helm :
	bash ${ADMIN_SRC_DIR}/${kps} installHelm4Latest

kps :=stack.sh
pull :
	bash ${ADMIN_SRC_DIR}/${kps} pull
inspect :
	bash ${ADMIN_SRC_DIR}/${kps} inspect
ldapca :
	bash ${ADMIN_SRC_DIR}/${kps} ldapCA
ldaptest :
	bash ${ADMIN_SRC_DIR}/${kps} ldapSearch
install upgrade apply :
	bash ${ADMIN_SRC_DIR}/${kps} install
access :
	bash ${ADMIN_SRC_DIR}/${kps} access
delete uninstall:
	pkill kubectl \
	    && echo "ℹ️ : Killing all kubectl processes" \
	    || echo "ℹ️ : No kubectl processes were running"
	bash ${ADMIN_SRC_DIR}/${kps} delete

admin :
	@kubectl get secret -n kps -l app.kubernetes.io/component=admin-secret -o jsonpath="{.items[0].data.admin-password}" | base64 --decode ; echo
