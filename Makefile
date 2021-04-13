.DEFAULT_GOAL := mac

#
#
# PROGRAMS / BINARIES
.PHONY: mac
mac: tilt
	brew install docker virtualbox docker-machine kubectl k3d k3sup terraform helm go jq node npm python docker-compose dive krew stern kustomize

.PHONY: tilt
tilt:
	curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash
	echo "n" | tilt analytics opt out

# .PHONY: popeye
# popeye:
# 	curl -L https://github.com/derailed/popeye/releases/download/v0.3.13/popeye_0.3.13_Linux_x86_64.tar.gz | tar -xzv -C /usr/local/bin/ popeye
# 	chmod a+x /usr/local/bin/popeye

# .PHONY: kubeent
# kubeent: ensure-sudo-access
# 	sh -c "$(curl -sSL 'https://git.io/install-kubent')"

# .PHONY: kontena-lens
# kontena-lens: ensure-sudo-access
# 	sudo snap install kontena-lens --classic

# .PHONY: portmaster
# portmaster: ensure-sudo-access
# 	curl -OL https://updates.safing.io/latest/linux_amd64/packages/portmaster-installer.deb
# 	sudo dpkg -i portmaster-installer.deb
# 	rm portmaster-installer.deb

# .PHONY: kube-bench
# kube-bench:
# 	curl -L https://github.com/aquasecurity/kube-bench/releases/download/v0.3.1/kube-bench_0.0.34_linux_amd64.tar.gz | tar xzv -C /usr/local/bin kube-bench
# 	chmod a+x /usr/local/bin/kube-bench

#
#
# DOCKER SETUP
.PHONY: docker-machine
docker-machine:
	docker-machine create --driver virtualbox default
	docker-machine env default
	@echo "Run 'eval "$(docker-machine env default)"' to load the environment variables to point to your docker VM in virtualbox."
	@echo "Run 'docker-machine stop default' to stop the VM."

.PHONY: docker-prune
docker-prune:
	docker ps -aq | xargs -I _ docker rm -fv _
	docker images -q | xargs -I _ docker rmi -f _
	docker system prune -af --volumes

#
#
# CLUSTER SETUP
.PHONY: setup-cluster
setup-cluster: k3d-create-cluster

#
#
# CLUSTER TOOLS
.PHONY: polaris-dashboard
polaris-dashboard:
	kubectl port-forward --namespace polaris svc/polaris-dashboard 8080:80

.PHONY: polaris-validating-webhook-helm
polaris-validating-webhook-helm:
	helm repo add fairwindsops-stable https://charts.fairwindsops.com/stable
	helm upgrade --install polaris fairwindsops-stable/polaris --namespace polaris --set webhook.enable=true --set dashboard.enable=false

polaris-validating-webhook-yaml:
	kubectl apply -f https://github.com/fairwindsops/polaris/releases/latest/download/webhook.yaml

# .PHONY: k3d-with-registry
# k3d-with-registry:
# 	curl -s https://raw.githubusercontent.com/windmilleng/k3d-local-registry/master/k3d-with-registry.sh > /usr/local/bin/k3d-with-registry.sh && chmod a+x "/usr/local/bin/k3d-with-registry.sh"

# .PHONY: local-registry
# local-registry: ensure-sudo-access
# 	docker volume create local_registry || echo "already created local registry"
# 	docker container run -d --name registry.localhost -v local_registry:/var/lib/registry --restart always -p 5000:5000 registry:2 || echo "----"

.PHONY: k3d-delete-cluster
k3d-delete-cluster:
	k3d cluster delete --all || echo "No existing clusters found."
	rm -f $(HOME)/.kube/config

.PHONY: k3d-create-cluster
k3d-create-cluster: k3d-delete-cluster local-registry
	ln -sf `k3d kubeconfig get mycluster` $(HOME)/.kube/config
	k3d cluster create mycluster

system-upgrade-controller-install:
	kustomize build github.com/rancher/system-upgrade-controller | kubectl apply -f -

#######
# LOGGING/MONITORING
# Prometheus, Logstash, Jaeger, other logging agents?, Thanos
#######

#######
# IDENTITY / KMS
# Vault, KeyCloak
#######

#######
# CI/CD
# Argo, ...
#######

#######
# SERVERLESS/BATCH
# knative, ...
#######

#######
# INGRESS CONTROLLERS
# istio?, ambassador, nginx, traefik, the on JPMorgan used...
#######
ambassador:
	helm repo add datawire https://www.getambassador.io
	kubectl create namespace ambassador
	helm install ambassador --namespace ambassador datawire/ambassador
	kubectl -n ambassador wait --for condition=available --timeout=90s deploy -lproduct=aes

ambassador-demo: ambassador
	kubectl apply -f https://www.getambassador.io/yaml/quickstart/qotm.yaml
	kubectl apply -f - <<EOF
	apiVersion: getambassador.io/v2
	kind: Mapping
	metadata:
		name: quote-backend
		namespace: ambassador
	spec:
		prefix: /backend/
		service: quote
	EOF
	kubectl -n ambassador get svc ambassador -o "go-template={{range .status.loadBalancer.ingress}}{{or .ip .hostname}}{{end}}"

#######
# SERVICE MESH
# TODO:solo, istiod, consul, linkerd,
#######

linkerd-bin:
	curl -sL https://run.linkerd.io/install | sh

linkerd-install:
	linkerd check --pre
	linkerd install | kubectl apply -f -
	# checks if control plane is setup
	linkerd check
	# linkerd dashboard to port forward to the linkerd-web pod
	# add linkerd sidecar with "cat file.yaml | linkerd inject - | kubectl apply -f -"
	# OR add linkerd to an existing deployment by getting the yaml from k8s and injecting
	#   "kubectl get deployment.. -o yaml | linkerd inject - | kubectl apply -f"
	# check if the proxy is setup correctly:
	#	 linkerd -n emojivoto check --proxy
	# get stats:
	#	linkerd stat --all-namespaces deploy
	# watch live requests/paths:
	#	linkerd -n emojivoto top deploy/web
	# or watch livetcp connections
	# 	linkerd -n emojivoto tap deploy/web