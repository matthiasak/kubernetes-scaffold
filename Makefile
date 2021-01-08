DOCKER_MISSING="Docker is missing from your PATH."
DOCKER_STOPPED="We were unable to invoke 'docker ps' -- is Docker running? is the daemon's socket file accessible to your current user?"
REDUCE_PERMISSIONS="Do not run this as the root user! Please re-run as your normal user"
EMAIL="..."
DIR=$(CURDIR)
UNAME := $(shell uname)
KIND_BINARY := "kind-linux-amd64"
HELM_BINARY := "linux-amd64"
DIVE_BINARY := "linux_amd64"
GO_VERSION := "1.15.5"
DIVE_VERSION := "0.9.2"

.PHONY: env
.DEFAULT_GOAL := env
env: ensure-not-root ensure-sudo-access ensure-docker ensure-usr-local-bin-writeable linux

.PHONY: linux
linux: docker-usermod k3d kind k8s-linux go-linux jq-linux tilt helm-v3 setup-cluster

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
setup-cluster: k3d-create-cluster

.PHONY: install-docker-ubuntu
install-docker-ubuntu:
	sudo apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	sudo apt-key fingerprint 0EBFCD88
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
	sudo apt install docker-ce

.PHONY: ensure-usr-local-bin-writeable
ensure-usr-local-bin-writeable: ensure-sudo-access
	@touch /usr/local/bin || sudo chown -R `whoami` /usr/local/bin

.PHONY: ensure-docker
ensure-docker:
	@which docker &> /dev/null || (echo $(DOCKER_MISSING) && exit 1)
	@docker ps &> /dev/null || (echo $(DOCKER_STOPPED) && exit 1)

.PHONY: kind
kind: ensure-usr-local-bin-writeable
	curl https://github.com/kubernetes-sigs/kind/releases/download/v0.9.0/$(KIND_BINARY) -o /usr/local/bin/kind --location
	chmod +x /usr/local/bin/kind

.PHONY: helm-v3
helm-v3: ensure-usr-local-bin-writeable
	curl -L https://get.helm.sh/helm-v3.4.2-$(HELM_BINARY).tar.gz | tar xzv -C /usr/local/bin --strip-components=1 $(HELM_BINARY)/helm
	chmod a+x /usr/local/bin/helm
	helm repo add stable https://charts.helm.sh/stable --force-update
	helm repo update


.PHONY: k8s-linux
k8s-linux: ensure-usr-local-bin-writeable
	curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
	chmod +x ./kubectl
	mv kubectl /usr/local/bin/kubectl

.PHONY: go-linux
go-linux: ensure-usr-local-bin-writeable
	curl -L https://dl.google.com/go/go$(GO_VERSION).linux-amd64.tar.gz | tar xzv -C /usr/local/bin --wildcards --strip-components=2 go/bin/*
	chmod +x /usr/local/bin/go
	chmod +x /usr/local/bin/godoc
	chmod +x /usr/local/bin/gofmt

.PHONY: jq-linux
jq-linux: ensure-usr-local-bin-writeable
	curl -L https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -o /usr/local/bin/jq
	chmod +x /usr/local/bin/jq

.PHONY: tilt
tilt:
	#curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash
	curl -fsSL https://github.com/tilt-dev/tilt/releases/download/v0.18.3/tilt.0.18.3.linux.x86_64.tar.gz | tar -xzv tilt
	sudo mv tilt /usr/local/bin/tilt
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

.PHONY: dive
dive:
	cd "$(mktemp -d)" && curl -L -O "https://github.com/wagoodman/dive/releases/download/v${DIVE_VERSION}/dive_${DIVE_VERSION}_${DIVE_BINARY}.tar.gz" && tar -xzf dive_${DIVE_VERSION}_${DIVE_BINARY}.tar.gz && mv dive /usr/local/bin/dive && chmod a+x /usr/local/bin/dive

.PHONY: krew
krew:
	# https://github.com/kubernetes-sigs/krew
	set -x; cd "$(mktemp -d)" && curl -fsSLO "https://storage.googleapis.com/krew/v0.2.1/krew.{tar.gz,yaml}" && tar zxvf krew.tar.gz && ./krew-"$(uname | tr '[:upper:]' '[:lower:]')_amd64" install --manifest=krew.yaml --archive=krew.tar.gz
	echo "Add '~/.krew/bin to your path, then you can use krew with kubectl ('kubectl krew ...')."

.PHONY: polaris-dashboard
polaris-dashboard:
	kubectl port-forward --namespace polaris svc/polaris-dashboard 8080:80

.PHONY: polaris-validating-webhook-helm
polaris-validating-webhook-helm:
	helm repo add fairwindsops-stable https://charts.fairwindsops.com/stable
	helm upgrade --install polaris fairwindsops-stable/polaris --namespace polaris --set webhook.enable=true --set dashboard.enable=false

polaris-validating-webhook-yaml:
	kubectl apply -f https://github.com/fairwindsops/polaris/releases/latest/download/webhook.yaml

# TODO: setup some CI/CD or githooks to use the CLI for validating?
# polaris-cli:
# 	curl

.PHONY: popeye
popeye:
	curl -L https://github.com/derailed/popeye/releases/download/v0.3.13/popeye_0.3.13_Linux_x86_64.tar.gz | tar -xzv -C /usr/local/bin/ popeye
	chmod a+x /usr/local/bin/popeye

.PHONY: stern
stern:
	wget https://github.com/wercker/stern/releases/download/1.11.0/stern_linux_amd64 -O /usr/local/bin/stern
	chmod a+x /usr/local/bin/stern

.PHONY: kube-bench
kube-bench:
	curl -L https://github.com/aquasecurity/kube-bench/releases/download/v0.3.1/kube-bench_0.0.34_linux_amd64.tar.gz | tar xzv -C /usr/local/bin kube-bench
	chmod a+x /usr/local/bin/kube-bench

.PHONY: k3sup
k3sup: ensure-sudo-access
	curl -sLS https://get.k3sup.dev | sh

.PHONY: k3d
k3d:
	curl -s https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash

# .PHONY: k3d-with-registry
# k3d-with-registry:
# 	curl -s https://raw.githubusercontent.com/windmilleng/k3d-local-registry/master/k3d-with-registry.sh > /usr/local/bin/k3d-with-registry.sh && chmod a+x "/usr/local/bin/k3d-with-registry.sh"

.PHONY: local-registry
local-registry: ensure-sudo-access
	docker volume create local_registry || echo "already created local registry"
	docker container run -d --name registry.localhost -v local_registry:/var/lib/registry --restart always -p 5000:5000 registry:2 || echo "----"
	docker network connect k3d-k3s-default registry.localhost || echo "----"
	sudo apt install libnss-myhostname
	cp ./yaml/k3d-registries.yaml ~/k3d-registries.yaml

.PHONY: k3d-delete-cluster
k3d-delete-cluster:
	k3d cluster delete --all || echo "No existing clusters found."
	rm -f $(HOME)/.kube/config ~/k3d-registries.yaml

.PHONY: k3d-create-cluster
k3d-create-cluster: k3d-delete-cluster local-registry
	ln -sf `k3d kubeconfig get mycluster` $(HOME)/.kube/config
	k3d cluster create mycluster --volume ~/k3d-registries.yaml:/etc/rancher/k3s/registries.yaml

.PHONY: kubeent
kubeent: ensure-sudo-access
	sh -c "$(curl -sSL 'https://git.io/install-kubent')"

.PHONY: kontena-lens
kontena-lens: ensure-sudo-access
	sudo snap install kontena-lens --classic

# Same binaries as https://releases.hashicorp.com/
.PHONY: hashi-apt
hashi-apt: ensure-sudo-access
	curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
	sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

.PHONY: portmaster
portmaster: ensure-sudo-access
	curl -OL https://updates.safing.io/latest/linux_amd64/packages/portmaster-installer.deb
	sudo dpkg -i portmaster-installer.deb
	rm portmaster-installer.deb