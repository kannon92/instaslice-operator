# VERSION defines the project version for the bundle.
# Update this value when you upgrade the version of your project.
# To re-generate a bundle for another specific version without changing the standard setup, you can:
# - use the VERSION as arg of the bundle target (e.g make bundle VERSION=0.0.2)
# - use environment variables to overwrite this value (e.g export VERSION=0.0.2)
VERSION ?= $(shell cat VERSION)

# CHANNELS define the bundle channels used in the bundle.
# Add a new line here if you would like to change its default config. (E.g CHANNELS = "candidate,fast,stable")
# To re-generate a bundle for other specific channels without changing the standard setup, you can:
# - use the CHANNELS as arg of the bundle target (e.g make bundle CHANNELS=candidate,fast,stable)
# - use environment variables to overwrite this value (e.g export CHANNELS="candidate,fast,stable")
ifneq ($(origin CHANNELS), undefined)
BUNDLE_CHANNELS := --channels=$(CHANNELS)
endif

# DEFAULT_CHANNEL defines the default channel used in the bundle.
# Add a new line here if you would like to change its default config. (E.g DEFAULT_CHANNEL = "stable")
# To re-generate a bundle for any other default channel without changing the default setup, you can:
# - use the DEFAULT_CHANNEL as arg of the bundle target (e.g make bundle DEFAULT_CHANNEL=stable)
# - use environment variables to overwrite this value (e.g export DEFAULT_CHANNEL="stable")
ifneq ($(origin DEFAULT_CHANNEL), undefined)
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
endif
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)

# IMAGE_TAG_BASE defines the docker.io namespace and part of the image name for remote images.
# This variable is used to construct full image tags for bundle and catalog images.
#
# For example, running 'make bundle-build bundle-push catalog-build catalog-push' will build and push both
# codeflare.dev/instaslice-operator-bundle:$VERSION and codeflare.dev/instaslice-operator-catalog:$VERSION.
IMAGE_TAG_BASE ?= quay.io/amalvank/instaslicev2
IMG_TAG ?= latest

# BUNDLE_IMG defines the image:tag used for the bundle.
# You can use it as an arg. (E.g make bundle-build BUNDLE_IMG=<some-registry>/<project-name-bundle>:<tag>)
BUNDLE_IMG ?= $(IMAGE_TAG_BASE)-bundle:$(IMG_TAG)

# BUNDLE_GEN_FLAGS are the flags passed to the operator-sdk generate bundle command
BUNDLE_GEN_FLAGS ?= -q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)

# OPERATOR_IMG define the image:tag used for the operator
# You can use it as an arg. (E.g make operator-build OPERATOR_IMG=<some-registry>:<version>)
OPERATOR_IMG ?= $(IMAGE_TAG_BASE)-operator:$(VERSION)

# USE_IMAGE_DIGESTS defines if images are resolved via tags or digests
# You can enable this value if you would like to use SHA Based Digests
# To enable set flag to true
USE_IMAGE_DIGESTS ?= false
ifeq ($(USE_IMAGE_DIGESTS), true)
	BUNDLE_GEN_FLAGS += --use-image-digests
endif

# Set the Operator SDK version to use. By default, what is installed on the system is used.
# This is useful for CI or a project to utilize a specific version of the operator-sdk toolkit.
OPERATOR_SDK_VERSION ?= v1.34.1

# Image URL to use all building/pushing image targets
IMG ?= $(IMAGE_TAG_BASE)-controller:$(IMG_TAG)
IMG_DMST ?= $(IMAGE_TAG_BASE)-daemonset:$(IMG_TAG)
# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.31.0

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# CONTAINER_TOOL defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_TOOL ?= docker

ifeq ($(CONTAINER_TOOL),podman)
MULTI_ARCH_OPTION=--manifest
else
MULTI_ARCH_OPTION=--push --provenance=false --tag
endif

KUSTOMIZATION ?= default
KIND ?= kind

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

# GOOS?=linux
# GOARCH?=arm64
# CGO_ENABLED?=0
# CLI_VERSION_PACKAGE := main
# COMMIT ?= $(shell git describe --dirty --long --always --abbrev=15)
# CGO_LDFLAGS_ALLOW := "-Wl,--unresolved-symbols=ignore-in-object-files"
# LDFLAGS_COMMON := "-s -w -X $(CLI_VERSION_PACKAGE).commitSha=$(COMMIT) -X $(CLI_VERSION_PACKAGE).version=$(VERSION)

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk command is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: manifests generate fmt vet envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path)" go test $$(go list ./... | grep -v /e2e) -coverprofile cover.out

# Utilize Kind or modify the e2e tests to load the image locally, enabling compatibility with other vendors.
.PHONY: test-e2e  # Run the e2e tests against a Kind k8s instance that is spun up.
test-e2e:
	@export IMG_TAG=test-e2e; make docker-build; go test ./test/e2e/ -v -ginkgo.v --timeout 20m

.PHONY: test-e2e-kind-emulated
test-e2e-kind-emulated: export IMG_TAG=test-e2e
test-e2e-kind-emulated: export KIND_NAME=kind-e2e
test-e2e-kind-emulated: export KIND_CONTEXT=kind-kind-e2e
test-e2e-kind-emulated: export KIND_NODE_NAME=${KIND_NAME}-control-plane
test-e2e-kind-emulated: export AUTO_LABEL_MANAGED_NODES=true
test-e2e-kind-emulated: export EMULATOR_MODE=true
test-e2e-kind-emulated: docker-build docker-push create-kind-cluster deploy-cert-manager deploy-instaslice-emulated-on-kind
	export KIND=$(KIND) KUBECTL=$(KUBECTL) IMG=$(IMG) IMG_DMST=$(IMG_DMST) && \
		ginkgo -v --json-report=report.json --junit-report=report.xml --timeout 20m ./test/e2e

.PHONY: cleanup-test-e2e-kind-emulated
cleanup-test-e2e-kind-emulated: KIND_NAME=kind-e2e
cleanup-test-e2e-kind-emulated:
	$(KIND) delete clusters ${KIND_NAME}

.PHONY: check-gpu-nodes
check-gpu-nodes:
    # Check for nodes with the label "nvidia.com/mig.capable=true"
	@if oc get nodes -l nvidia.com/mig.capable=true --no-headers | grep -q '.'; then \
	    echo "Error: Nodes with label 'nvidia.com/mig.capable=true' exist. Cannot run in emulated mode."; \
	    exit 1; \
	fi

.PHONY: test-e2e-ocp-emulated
test-e2e-ocp-emulated: container-build-ocp docker-push bundle-ocp-emulated bundle-build-ocp bundle-push deploy-cert-manager-ocp deploy-instaslice-on-ocp
	hack/label-node.sh
	$(eval FOCUS_ARG := $(if $(FOCUS),--focus="$(FOCUS)"))
	EMULATOR_MODE=true AUTO_LABEL_MANAGED_NODES=true ginkgo -v --json-report=report.json --junit-report=report.xml --timeout 20m $(FOCUS_ARG) ./test/e2e

PHONY: cleanup-test-e2e-ocp-emulated
cleanup-test-e2e-ocp-emulated: KUBECTL=oc
cleanup-test-e2e-ocp-emulated: ocp-undeploy-emulated

.PHONY: test-e2e-ocp
test-e2e-ocp: wait-for-instaslice-operator-stable
test-e2e-ocp: export EMULATOR_MODE=false
test-e2e-ocp: export AUTO_LABEL_MANAGED_NODES=true
test-e2e-ocp:
	$(eval FOCUS_ARG := $(if $(FOCUS),--focus="$(FOCUS)"))
	ginkgo -v --json-report=report.json --junit-report=report.xml --timeout 20m $(FOCUS_ARG) ./test/e2e

PHONY: cleanup-test-e2e-ocp
cleanup-test-e2e-ocp: KUBECTL=oc
cleanup-test-e2e-ocp: ocp-undeploy

wait-for-instaslice-operator-stable:
	@echo "---- Waiting for instaslice-operator stable state ----"
	oc wait --for=condition=Available deployment/instaslice-operator-controller-manager \
		-n instaslice-system --timeout=120s || $(MAKE) test-e2e-debug-instaslice
	oc rollout status daemonset/instaslice-operator-controller-daemonset \
		-n instaslice-system --timeout=120s || $(MAKE) test-e2e-debug-instaslice
	@echo "---- /Waiting for instaslice-operator stable state ----"
.PHONY: wait-for-instaslice-operator-stable

test-e2e-debug-instaslice:
	@echo "---- Debugging instaslice-operator current state ----"
	- oc get pod -n instaslice-system
	- oc get ds -n instaslice-system
	- oc get deployments -n instaslice-system
	- oc logs deployment/instaslice-operator-controller-manager -n instaslice-system
	- oc logs daemonset/instaslice-operator-controller-daemonset -n instaslice-system
	@echo "---- /Debugging instaslice-operator current state ----"
.PHONY: test-e2e-debug-instaslice

# requires cert-manager and instaslice operators to be install (EMULATOR_MODE: false)
.PHONY: test-e2e-konflux
test-e2e-konflux: wait-for-instaslice-operator-stable
	# the following is for when we need to ship konflux builds and test with emulated mode enabled post install
	# oc patch csv/instaslice-operator.v0.0.2 --type=json --patch-file hack/emulator_mode-patch.json
	# oc rollout status deployment/instaslice-operator-controller-manager -n instaslice-system
	# oc delete daemonset/instaslice-operator-controller-daemonset -n instaslice-system
	# @echo "---- Waiting for daemonset to get recreated ----"
	# # sleep 10
	# @if oc get daemonset -n instaslice-system; then echo "daemonset was created"; \
	# else exit 1; \
	# fi
	hack/label-node.sh
	go run ./vendor/github.com/onsi/ginkgo/v2/ginkgo -v --json-report=report.json --junit-report=report.xml --timeout 20m ./test/e2e

.PHONY: create-kind-cluster
create-kind-cluster:
	export KIND=$(KIND) KUBECTL=$(KUBECTL) IMG=$(IMG) IMG_DMST=$(IMG_DMST) && \
		hack/create-kind-cluster.sh

.PHONY: destroy-kind-cluster
destroy-kind-cluster:
	export KIND=$(KIND) KUBECTL=$(KUBECTL) IMG=$(IMG) IMG_DMST=$(IMG_DMST) && \
                hack/destroy-kind-cluster.sh

.PHONY: deploy-cert-manager
deploy-cert-manager:
	export KUBECTL=$(KUBECTL) IMG=$(IMG) IMG_DMST=$(IMG_DMST) && \
                hack/deploy-cert-manager.sh

.PHONY: deploy-cert-manager-ocp
deploy-cert-manager-ocp:
	oc apply -f hack/manifests/cert-manager-rh.yaml

.PHONY: undeploy-cert-manager-ocp
undeploy-cert-manager-ocp:
	oc delete -f hack/manifests/cert-manager-rh.yaml

.PHONY: deploy-nfd-ocp
deploy-nfd-ocp:
	hack/deploy-nfd.sh

.PHONY: undeploy-nfd-ocp
undeploy-nfd-ocp:
	oc delete -f hack/manifests/nfd-instance.yaml
	oc delete -f hack/manifests/nfd.yaml

.PHONY: deploy-nvidia-ocp
deploy-nvidia-ocp:
	hack/deploy-nvidia.sh

.PHONY: undeploy-nvidia-ocp
undeploy-nvidia-ocp:
	oc delete -f hack/manifests/gpu-cluster-policy.yaml
	oc delete -f hack/manifests/nvidia-cpu-operator.yaml

.PHONY: deploy-instaslice-emulated-on-kind
deploy-instaslice-emulated-on-kind:
	export KIND=$(KIND) KUBECTL=$(KUBECTL) IMG=$(IMG) IMG_DMST=$(IMG_DMST) && \
		hack/deploy-instaslice-emulated-on-kind.sh

.PHONY: deploy-instaslice-on-ocp
deploy-instaslice-on-ocp:
	oc new-project instaslice-system
	operator-sdk run bundle ${BUNDLE_IMG} -n instaslice-system

.PHONY: undeploy-instaslice-on-ocp
undeploy-instaslice-on-ocp:
	oc delete ns/instaslice-system

GOLANGCI_LINT = $(shell pwd)/bin/golangci-lint
GOLANGCI_LINT_VERSION ?= v1.61.0
golangci-lint:
	@[ -f $(GOLANGCI_LINT) ] || { \
	set -e ;\
	curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(shell dirname $(GOLANGCI_LINT)) $(GOLANGCI_LINT_VERSION) ;\
	}

.PHONY: lint
lint: golangci-lint ## Run golangci-lint linter & yamllint
	$(GOLANGCI_LINT) run --timeout 5m

.PHONY: lint-fix
lint-fix: golangci-lint ## Run golangci-lint linter and perform fixes
	$(GOLANGCI_LINT) run --fix

##@ Build

.PHONY: build
build: manifests generate fmt vet ## Build manager binary.
	go build -o bin/manager cmd/controller/main.go
	go build -o bin/daemonset cmd/daemonset/main.go

.PHONY: run-controller
run-controller: manifests generate fmt vet ## Run a controller from your host.
	sudo -E go run ./cmd/controller/main.go

.PHONY: run-daemonset
run-daemonset: manifests generate fmt vet ## Run a controller from your host.
	sudo -E go run ./cmd/daemonset/main.go

# If you wish to build the manager image targeting other platforms you can use the --platform flag.
# (i.e. docker build --platform linux/arm64). However, you must enable docker buildKit for it.
# More info: https://docs.docker.com/develop/develop-images/build_enhancements/
.PHONY: docker-build
docker-build: ## Build docker image with the manager.
	$(CONTAINER_TOOL) build -t ${IMG} -f Dockerfile.controller .
	$(CONTAINER_TOOL) build -t ${IMG_DMST} -f Dockerfile.daemonset .

.PHONY: container-build-ocp
container-build-ocp: ## Build docker image with the manager.
	$(CONTAINER_TOOL) build -t ${IMG} -f Dockerfile.ocp .
	$(CONTAINER_TOOL) build -t ${IMG_DMST} -f Dockerfile.daemonset-ocp .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	$(CONTAINER_TOOL) push ${IMG}
	$(CONTAINER_TOOL) push ${IMG_DMST}

# PLATFORMS defines the target platforms for the manager image be built to provide support to multiple
# architectures. Make sure that base image in the Dockerfile/Containerfile is itself multi-platform, and includes
# the requested plaforms. Unlike "docker buildx", for multi-platform images podman requires creating a manifest.
PLATFORMS ?= linux/arm64,linux/amd64
.PHONY: docker-buildx
docker-buildx: ## Build and push docker images with multi-platform support
	if [ "$(CONTAINER_TOOL)" == "podman" ]; then \
	  $(CONTAINER_TOOL) manifest rm ${IMG} || true; \
	  $(CONTAINER_TOOL) manifest create ${IMG}; \
	  $(CONTAINER_TOOL) manifest rm ${IMG_DMST} || true; \
	  $(CONTAINER_TOOL) manifest create ${IMG_DMST}; \
	fi
	DOCKER_BUILDKIT=1 $(CONTAINER_TOOL) buildx build --platform=$(PLATFORMS) $(MULTI_ARCH_OPTION) ${IMG} -f Dockerfile.controller .
	DOCKER_BUILDKIT=1 $(CONTAINER_TOOL) buildx build --platform=$(PLATFORMS) $(MULTI_ARCH_OPTION) ${IMG_DMST} -f Dockerfile.daemonset .
	if [ "$(CONTAINER_TOOL)" == "podman" ]; then \
	  $(CONTAINER_TOOL) manifest push ${IMG}; \
	  $(CONTAINER_TOOL) manifest push ${IMG_DMST}; \
	fi

.PHONY: build-installer
build-installer: manifests generate kustomize ## Generate a consolidated YAML with CRDs and deployment.
	mkdir -p dist
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/$(KUSTOMIZATION) > dist/install.yaml

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/$(KUSTOMIZATION) | sed -e "s|<IMG_DMST>|$(IMG_DMST)|g" | $(KUBECTL) apply -f -

.PHONY: deploy-dry-run
deploy-dry-run: manifests kustomize ## Perform a dry-run deployment and save output to deploy-dry-run.yaml.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/$(KUSTOMIZATION) | sed -e "s|<IMG_DMST>|$(IMG_DMST)|g" | $(KUBECTL) apply --dry-run=client -f - > deploy-dry-run.yaml

.PHONY: ocp-deploy
ocp-deploy: container-build-ocp docker-push bundle-ocp bundle-build-ocp bundle-push deploy-instaslice-on-ocp

.PHONY: deploy-emulated ## Deploy controller in emulator mode
deploy-emulated: KUSTOMIZATION=emulator
deploy-emulated: deploy

.PHONY: ocp-deploy-emulated ## Deploy controller in emulator mode in Openshift
ocp-deploy-emulated: KUSTOMIZATION=emulator
ocp-deploy-emulated: ocp-deploy

# .PHONY: deploy-daemonset
# deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
# 	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG_DMST}
# 	$(KUSTOMIZE) build config/daemonset | $(KUBECTL) apply -f -

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/$(KUSTOMIZATION) | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: ocp-undeploy
ocp-undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/$(KUSTOMIZATION) | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -
	$(KUBECTL) delete -f config/rbac-ocp/instaslice-operator-scc.yaml
	$(KUBECTL) delete -f config/rbac-ocp/openshift_scc_cluster_role_binding.yaml
	$(KUBECTL) apply -f config/rbac-ocp/openshift_cluster_role.yaml

.PHONY: undeploy-emulated
undeploy-emulated: KUSTOMIZATION=emulator ## Undeploy controller deployed in emulator mode
undeploy-emulated: undeploy

.PHONY: ocp-undeploy-emulated
ocp-undeploy-emulated: KUSTOMIZATION=emulator ## Undeploy controller deployed in emulator mode in Openshift
ocp-undeploy-emulated: ocp-undeploy

##@ Build Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
KUBECTL ?= kubectl
KUSTOMIZE ?= $(LOCALBIN)/kustomize
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
ENVTEST ?= $(LOCALBIN)/setup-envtest

## Tool Versions
KUSTOMIZE_VERSION ?= v5.3.0
CONTROLLER_TOOLS_VERSION ?= v0.16.4

.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary. If wrong version is installed, it will be removed before downloading.
$(KUSTOMIZE): $(LOCALBIN)
	@if test -x $(LOCALBIN)/kustomize && ! $(LOCALBIN)/kustomize version | grep -q $(KUSTOMIZE_VERSION); then \
		echo "$(LOCALBIN)/kustomize version is not expected $(KUSTOMIZE_VERSION). Removing it before installing."; \
		rm -rf $(LOCALBIN)/kustomize; \
	fi
	test -s $(LOCALBIN)/kustomize || GOBIN=$(LOCALBIN) GO111MODULE=on go install sigs.k8s.io/kustomize/kustomize/v5@$(KUSTOMIZE_VERSION)

.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary. If wrong version is installed, it will be overwritten.
$(CONTROLLER_GEN): $(LOCALBIN)
	test -s $(LOCALBIN)/controller-gen && $(LOCALBIN)/controller-gen --version | grep -q $(CONTROLLER_TOOLS_VERSION) || \
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)

.PHONY: envtest
envtest: $(ENVTEST) ## Download envtest-setup locally if necessary.
$(ENVTEST): $(LOCALBIN)
	test -s $(LOCALBIN)/setup-envtest || GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest

.PHONY: operator-sdk
OPERATOR_SDK ?= $(LOCALBIN)/operator-sdk
operator-sdk: ## Download operator-sdk locally if necessary.
ifeq (,$(wildcard $(OPERATOR_SDK)))
ifeq (, $(shell which operator-sdk 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPERATOR_SDK)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(OPERATOR_SDK) https://github.com/operator-framework/operator-sdk/releases/download/$(OPERATOR_SDK_VERSION)/operator-sdk_$${OS}_$${ARCH} ;\
	chmod +x $(OPERATOR_SDK) ;\
	}
else
OPERATOR_SDK = $(shell which operator-sdk)
endif
endif

.PHONY: bundle
bundle: manifests kustomize operator-sdk ## Generate bundle manifests and metadata, then validate generated files.
	$(OPERATOR_SDK) generate kustomize manifests -q
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/manifests | sed -e "s|<IMG>|$(IMG)|g" | sed -e "s|<IMG_DMST>|$(IMG_DMST)|g" | $(OPERATOR_SDK) generate bundle $(BUNDLE_GEN_FLAGS)
	$(OPERATOR_SDK) bundle validate ./bundle

.PHONY: bundle-ocp
bundle-ocp: manifests kustomize operator-sdk ## Generate bundle manifests and metadata, then validate generated files.
	# $(OPERATOR_SDK) generate kustomize manifests --output-dir config/manifests-ocp -q ## stomps on custom csv
	cd config/manager-ocp && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build --load-restrictor LoadRestrictionsNone config/manifests-ocp | sed -e "s|<IMG>|$(IMG)|g" | sed -e "s|<IMG_DMST>|$(IMG_DMST)|g" | $(OPERATOR_SDK) generate bundle $(BUNDLE_GEN_FLAGS) --output-dir bundle-ocp --overwrite=false
	$(OPERATOR_SDK) bundle validate ./bundle-ocp

.PHONY: bundle-ocp-emulated
bundle-ocp-emulated: manifests kustomize operator-sdk ## Generate bundle manifests and metadata, then validate generated files.
	# $(OPERATOR_SDK) generate kustomize manifests --output-dir config/manifests-ocp-emulated -q  ## stomps on custom csv
	cd config/manager-ocp && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build --load-restrictor LoadRestrictionsNone config/manifests-ocp-emulated | sed -e "s|<IMG>|$(IMG)|g" | sed -e "s|<IMG_DMST>|$(IMG_DMST)|g" | $(OPERATOR_SDK) generate bundle $(BUNDLE_GEN_FLAGS) --output-dir bundle-ocp --overwrite=false
	$(OPERATOR_SDK) bundle validate ./bundle-ocp

.PHONY: bundle-build
bundle-build: ## Build the bundle image.
	$(CONTAINER_TOOL) build -f bundle.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: bundle-build-ocp
bundle-build-ocp: ## Build the bundle image.
	$(CONTAINER_TOOL) build -f bundle-ocp.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: bundle-push
bundle-push: ## Push the bundle image.
	$(CONTAINER_TOOL) push ${BUNDLE_IMG}

.PHONY: opm
OPM = $(LOCALBIN)/opm
opm: ## Download opm locally if necessary.
ifeq (,$(wildcard $(OPM)))
ifeq (,$(shell which opm 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPM)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(OPM) https://github.com/operator-framework/operator-registry/releases/download/v1.23.0/$${OS}-$${ARCH}-opm ;\
	chmod +x $(OPM) ;\
	}
else
OPM = $(shell which opm)
endif
endif

# A comma-separated list of bundle images (e.g. make catalog-build BUNDLE_IMGS=example.com/operator-bundle:v0.1.0,example.com/operator-bundle:v0.2.0).
# These images MUST exist in a registry and be pull-able.
BUNDLE_IMGS ?= $(BUNDLE_IMG)

# The image tag given to the resulting catalog image (e.g. make catalog-build CATALOG_IMG=example.com/operator-catalog:v0.2.0).
CATALOG_IMG ?= $(IMAGE_TAG_BASE)-catalog:v$(VERSION)

# Set CATALOG_BASE_IMG to an existing catalog image tag to add $BUNDLE_IMGS to that image.
ifneq ($(origin CATALOG_BASE_IMG), undefined)
FROM_INDEX_OPT := --from-index $(CATALOG_BASE_IMG)
endif

# Build a catalog image by adding bundle images to an empty catalog using the operator package manager tool, 'opm'.
# This recipe invokes 'opm' in 'semver' bundle add mode. For more information on add modes, see:
# https://github.com/operator-framework/community-operators/blob/7f1438c/docs/packaging-operator.md#updating-your-existing-operator
.PHONY: catalog-build
catalog-build: opm ## Build a catalog image.
	$(OPM) index add --container-tool docker --mode semver --tag $(CATALOG_IMG) --bundles $(BUNDLE_IMGS) $(FROM_INDEX_OPT)

# Push the catalog image.
.PHONY: catalog-push
catalog-push: ## Push a catalog image.
	$(MAKE) docker-push IMG=$(CATALOG_IMG)
