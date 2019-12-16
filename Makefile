BREW_MISSING="Brew is missing from your PATH. Install brew (https://brew.sh/) and/or fix your config, then re-run this script."
DOCKER_MISSING="Docker is missing from your PATH."
DOCKER_STOPPED="We were unable to invoke 'docker ps' -- is Docker running? is the daemon's socket file accessible to your current user?"
REDUCE_PERMISSIONS="Do not run this as the root user! Please re-run as your normal user"
EMAIL="..."
DIR=$(CURDIR)
UNAME := $(shell uname)

ifeq ($(UNAME),Darwin)
	IS_MAC := 1
	IS_LINUX := 0
	KIND_BINARY := "kind-darwin-amd64"
	HELM_BINARY := "darwin-amd64"
	DIVE_BINARY := "darwin_amd64
else
	IS_MAC := 0
	IS_LINUX := 1
	KIND_BINARY := "kind-linux-amd64"
	HELM_BINARY := "linux-amd64"
	DIVE_BINARY := "linux_amd64"
endif

GO_VERSION := "1.12.9"
DIVE_VERSION := "0.8.1"

.PHONY: env
.DEFAULT_GOAL := env
env: ensure-not-root ensure-sudo-access ensure-docker ensure-usr-local-bin-writeable
	echo "STARTING BUILD..."
ifeq ($(IS_MAC), 1)
	$(MAKE) mac 2>&1 | tee $(LOG_FILE)
else
	$(MAKE) linux 2>&1 | tee $(LOG_FILE)
endif

.PHONY: mac
mac: ensure-xcode k3d k8s-mac go-mac jq-mac kubefwd-mac tilt-mac helm-v3 setup-cluster

.PHONY: linux
linux: docker-usermod k3d k8s-linux go-linux jq-linux kubefwd-linux tilt-linux helm-v3 setup-cluster

.PHONY: ensure-sudo-access
ensure-sudo-access:
	@echo "Prepping for later sudo use.... please enter your password if prompted:"
	@sudo whoami

.PHONY: ensure-not-root
ensure-not-root:
	@env | grep "^USER=" | grep -v "root" || (echo $(REDUCE_PERMISSIONS) && exit 1)

.PHONY: hard-purge-containers
hard-purge-containers: ensure-sudo-access
	sudo service docker stop
	for dir in `sudo ls /var/lib/docker/containers/`; do sudo rm -rf /var/lib/docker/containers/${dir}; done
	sudo service docker start

.PHONY: setup-cluster
setup-cluster: k3d-create-cluster nginx kubedb

.PHONY: install-docker-ubuntu
install-docker-ubuntu:
	sudo apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	sudo apt-key fingerprint 0EBFCD88
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
	sudo apt install docker-ce

.PHONY: microk8s
microk8s: ensure-sudo-access
	test `which microk8s.enable`="" && sudo snap install microk8s --classic && microk8s.enable && microk8s.start || echo "microk8s already installed"
	mkdir -p ~/.kube
	microk8s.config > ~/.kube/config
	microk8s.enable dns registry storage

.PHONY: ensure-xcode
ensure-xcode:
	@xcode-select --install || echo "xcode already installed."

.PHONY: ensure-usr-local-bin-writeable
ensure-usr-local-bin-writeable: ensure-sudo-access
	@touch /usr/local/bin || sudo chown -R `whoami` /usr/local/bin

.PHONY: ensure-docker
ensure-docker:
	@which docker &> /dev/null || (echo $(DOCKER_MISSING) && exit 1)
	@docker ps &> /dev/null || (echo $(DOCKER_STOPPED) && exit 1)

.PHONY: ensure-brew
ensure-brew:
	@which brew || (echo $(BREW_MISSING) && exit 1)

.PHONY: kind
kind: ensure-usr-local-bin-writeable
	curl https://github.com/kubernetes-sigs/kind/releases/download/v0.5.1/$(KIND_BINARY) -o /usr/local/bin/kind --location
	chmod +x /usr/local/bin/kind

.PHONY: helm-v3
helm-v3: ensure-usr-local-bin-writeable
	curl -L https://get.helm.sh/helm-v3.0.1-$(HELM_BINARY).tar.gz | tar xzv -C /usr/local/bin --strip-components=1 $(HELM_BINARY)/helm
	chmod a+x /usr/local/bin/helm

.PHONY: k8s-mac
k8s-mac: ensure-brew
	brew upgrade kubernetes-cli || brew install kubernetes-cli
	brew link --overwrite kubernetes-cli

.PHONY: k8s-linux
k8s-linux: ensure-usr-local-bin-writeable
	curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
	chmod +x ./kubectl
	mv kubectl /usr/local/bin/kubectl

.PHONY: go-mac
go-mac: ensure-brew
	brew upgrade go || brew install go

.PHONY: go-linux
go-linux: ensure-usr-local-bin-writeable
	curl -L https://dl.google.com/go/go$(GO_VERSION).linux-amd64.tar.gz | tar xzv -C /usr/local/bin --wildcards --strip-components=2 go/bin/*
	chmod +x /usr/local/bin/go
	chmod +x /usr/local/bin/godoc
	chmod +x /usr/local/bin/gofmt

.PHONY: jq-mac
jq-mac: ensure-brew
	brew upgrade jq || brew install jq

.PHONY: jq-linux
jq-linux: ensure-usr-local-bin-writeable
	curl -L https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -o /usr/local/bin/jq
	chmod +x /usr/local/bin/jq

.PHONY: kubefwd-mac
kubefwd-mac: ensure-brew
	brew upgrade txn2/tap/kubefwd || brew install txn2/tap/kubefwd

.PHONY: kubefwd-linux
kubefwd-linux: ensure-usr-local-bin-writeable
	curl -L https://github.com/txn2/kubefwd/releases/download/v1.8.3/kubefwd_linux_amd64.tar.gz | tar xzv kubefwd && mv kubefwd /usr/local/bin/kubefwd

.PHONY: tilt-mac
tilt-mac: ensure-brew
	brew tap windmilleng/tap
	brew upgrade windmilleng/tap/tilt || brew install windmilleng/tap/tilt
	@echo "n" | tilt analytics opt out

.PHONY: tilt-linux
tilt-linux: ensure-usr-local-bin-writeable
	curl -s https://api.github.com/repos/windmilleng/tilt/releases/latest | jq -r '.assets[] | select(.name|match("linux.x86_64")) | .browser_download_url' | xargs -I _ curl -L _ | tar -xzv tilt
	mv tilt /usr/local/bin/tilt
	echo "n" | tilt analytics opt out

.PHONY: kind-delete-cluster
kind-delete-cluster:
	echo "WARNING: If the following command hangs on linux for more than 5 minutes: control-C, run 'make hard-purge-containers', and re-run your current make command"
	kind delete cluster || echo "No existing clusters found."
	echo "END WARNING"
	rm -f $(HOME)/.kube/config

.PHONY: kind-create-cluster
kind-create-cluster: kind-delete-cluster ensure-sudo-access
	kind create cluster
	ln -sf `kind get kubeconfig-path` $(HOME)/.kube/config

.PHONY: docker-prune
docker-prune:
	docker ps -aq | xargs -I _ docker rm -fv _
	docker images -q | xargs -I _ docker rmi -f _
	docker system prune -af --volumes

.PHONY: docker-usermod
docker-usermod: ensure-sudo-access
	sudo usermod -aG docker $(USER)
	sudo systemctl enable docker
	sudo systemctl restart docker

.PHONY: istio
istio:
	kubectl delete namespace istio-system &> /dev/null || echo "istio-system namespace not setup."
	kubectl create namespace istio-system
	helm repo add istio.io https://storage.googleapis.com/istio-release/releases/1.2.4/charts/
	helm install istio-init istio.io/istio-init --namespace istio-system
	while [ `kubectl api-resources --api-group=config.istio.io -o wide --no-headers | wc -l | awk '{print $1}'` -eq 0 ]; do sleep 1; done
	helm install istio istio.io/istio --namespace istio-system --set certmanager.email=$(EMAIL) --set nodeagent.enabled=false
	kubectl label namespace default istio-injection=enabled
	kubectl apply -f $(DIR)/yaml/istio.global-resources.yaml


.PHONY: nginx
nginx:
	helm repo add stable https://kubernetes-charts.storage.googleapis.com/
	helm upgrade --install ingress stable/nginx-ingress --set rbac.create=true --set serviceAccount.create=true --set controller.service.type=ClusterIP


.PHONY: kubedb
kubedb:
	curl -fsSL https://raw.githubusercontent.com/kubedb/cli/0.12.0/hack/deploy/kubedb.sh | bash -s

.PHONY: exec-alpine
exec-alpine:
	kubectl run -it alpine --image=alpine:latest --restart=Never --rm -- sh

.PHONY: certmanager
certmanager:
	helm upgrade --install cert-manager --namespace ingress --set ingressShim.defaultIssuerName=letsencrypt-prod --set ingressShim.defaultIssuerKind=ClusterIssuer stable/cert-manager
	helm install --name cert-manager --namespace ingress --set ingressShim.defaultIssuerName=letsencrypt-prod --set ingressShim.defaultIssuerKind=ClusterIssuer stable/cert-manager
	envsubst < $(DIR)yaml/certmanager-prod.yaml | kubectl apply -n ingress -f -

.PHONY: dive
dive:
	cd "$(mktemp -d)" && curl -L -O "https://github.com/wagoodman/dive/releases/download/v${DIVE_VERSION}/dive_${DIVE_VERSION}_${DIVE_BINARY}.tar.gz" && tar -xzf dive_${DIVE_VERSION}_${DIVE_BINARY}.tar.gz && mv dive /usr/local/bin/dive && chmod a+x /usr/local/bin/dive

.PHONY: krew
krew:
	# https://github.com/kubernetes-sigs/krew
	set -x; cd "$(mktemp -d)" && curl -fsSLO "https://storage.googleapis.com/krew/v0.2.1/krew.{tar.gz,yaml}" && tar zxvf krew.tar.gz && ./krew-"$(uname | tr '[:upper:]' '[:lower:]')_amd64" install --manifest=krew.yaml --archive=krew.tar.gz
	echo "Add '~/.krew/bin to your path, then you can use krew with kubectl ('kubectl krew ...')."

.PHONY: polaris
polaris:
	helm repo add fairwinds-stable https://charts.fairwinds.com/stable
	helm upgrade --install polaris fairwinds-stable/polaris --namespace polaris

.PHONY: polaris-dashboard
polaris-dashboard:
	kubectl port-forward --namespace polaris svc/polaris-dashboard 8080:80

.PHONY: popeye
popeye:
	curl -L https://github.com/derailed/popeye/releases/download/v0.3.13/popeye_0.3.13_Linux_x86_64.tar.gz | tar -xzv -C /usr/local/bin/ popeye
	chmod a+x /usr/local/bin/popeye

.PHONY: stern
stern:
	wget https://github.com/wercker/stern/releases/download/1.10.0/stern_linux_amd64 -O /usr/local/bin/stern
	chmod a+x /usr/local/bin/stern

.PHONY: kube-bench
kube-bench:
	curl -L https://github.com/aquasecurity/kube-bench/releases/download/v0.0.34/kube-bench_0.0.34_linux_amd64.tar.gz | tar xzv -C /usr/local/bin kube-bench
	chmod a+x /usr/local/bin/kube-bench

.PHONY: img-tool
img-tool:
	curl -fSL "https://github.com/genuinetools/img/releases/download/v0.5.7/img-linux-amd64" -o "/usr/local/bin/img" && chmod a+x "/usr/local/bin/img"

clear-linux-runc:
	sudo swupd bundle-add cloud-control cloud-native-basic
	sudo docker-set-default-runtime -r runc

.PHONY: k3d
k3d:
	curl -s https://raw.githubusercontent.com/rancher/k3d/master/install.sh | bash

.PHONY: k3d-delete-cluster
k3d-delete-cluster:
	k3d d -a || echo "No existing clusters found."
	echo "END WARNING"
	rm -f $(HOME)/.kube/config

.PHONY: k3d-create-cluster
k3d-create-cluster: k3d-delete-cluster k3d-local-registry
	k3d create --publish 8080:80 8443:443 --wait 0 --auto-restart --volume /home/${USER}/.k3d/config.toml.tmpl:/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
	docker network connect k3d-k3s-default registry.local
	echo "127.0.0.1 registry.local" | sudo tee -a /etc/hosts
	k3d start
	sleep 10
	ln -sf `k3d get-kubeconfig` $(HOME)/.kube/config

.PHONY: k3d-local-registry
k3d-local-registry:
	docker container rm --force registry.local && docker volume rm local_registry || echo "registry currently not running"
	docker volume create local_registry
	docker container run -d --name registry.local -v local_registry:/var/lib/registry --restart always -p 5000:5000 registry:2
	mkdir -p /home/${USER}/.k3d
	cat yaml/config.toml.tmpl > /home/$(USER)/.k3d/config.toml.tmpl
