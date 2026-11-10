GO    := GO111MODULE=on go
PROMU := $(GOPATH)/bin/promu
pkgs   = $(shell $(GO) list ./... | grep -v /vendor/)
UNAME_S := $(shell uname -s | tr A-Z a-z)
UNAME_M := $(shell uname -m)

ifeq ($(findstring aarch64,$(UNAME_M)),aarch64)
    ARCH := arm64
else
    ARCH := $(subst x86_64,amd64,$(patsubst i%86,386,$(UNAME_M)))
endif

PREFIX                  ?= $(shell pwd)
BIN_DIR                 ?= $(shell pwd)
DOCKER_REGISTRY         ?= ghcr.io
DOCKER_USERNAME         ?= $(shell git config --get remote.origin.url | sed -E 's#.*[:/]([^/]+)/[^/]+(\.git)?$$#\1#' | tr '[:upper:]' '[:lower:]')
DOCKER_IMAGE_NAME       ?= kafka_exporter
DOCKER_IMAGE            ?= $(DOCKER_REGISTRY)/$(shell echo '$(DOCKER_USERNAME)' | tr '[:upper:]' '[:lower:]')/$(DOCKER_IMAGE_NAME)
DOCKER_IMAGE_TAG        ?= $(subst /,-,$(shell git rev-parse --abbrev-ref HEAD))
DOCKER_BUILDER          ?= kafka-exporter-builder
#TAG 					:= $(shell echo `if [ "$(TRAVIS_BRANCH)" = "master" ] || [ "$(TRAVIS_BRANCH)" = "" ] ; then echo "latest"; else echo $(TRAVIS_BRANCH) ; fi`)

PUSHTAG                 ?= type=registry,push=true
DOCKER_PLATFORMS        ?= linux/amd64,linux/s390x,linux/arm64,linux/ppc64le
# Platforms that actually ship in the docker image, so the build context stays small.
CROSSBUILD_PLATFORMS    ?= linux/(amd64|arm64|ppc64le|s390x)
GIT_TAG_NAME            ?= $(shell git describe --tags --exact-match 2>/dev/null || echo latest)

all: format build test

style:
	@echo ">> checking code style"
	@! gofmt -d $(shell find . -path ./vendor -prune -o -name '*.go' -print) | grep '^'

test:
	@echo ">> running tests"
	@$(GO) test -short $(pkgs)

format:
	@echo ">> formatting code"
	@$(GO) fmt $(pkgs)

vet:
	@echo ">> vetting code"
	@$(GO) vet $(pkgs)

build: promu
	@echo ">> building binaries"
	@$(GO) mod vendor
	@$(PROMU) build --prefix $(PREFIX)


crossbuild: promu
	@echo ">> crossbuilding binaries"
	@$(PROMU) crossbuild --go=1.27

crossbuild-docker: promu
	@echo ">> crossbuilding binaries for $(DOCKER_PLATFORMS)"
	@$(PROMU) crossbuild --go=1.27 --platforms '$(CROSSBUILD_PLATFORMS)'

tarball: promu
	@echo ">> building release tarball"
	@$(PROMU) tarball --prefix $(PREFIX) $(BIN_DIR)

docker: build
	@echo ">> building docker image $(DOCKER_IMAGE):$(DOCKER_IMAGE_TAG)"
	@docker build -t "$(DOCKER_IMAGE):$(DOCKER_IMAGE_TAG)" --build-arg BIN_DIR=. .

push: crossbuild-docker
	@echo ">> building and pushing multi-arch docker image $(DOCKER_IMAGE):$(GIT_TAG_NAME)"
	@if [ -n "$(DOCKER_PASSWORD)" ]; then \
		echo "$(DOCKER_PASSWORD)" | docker login "$(DOCKER_REGISTRY)" -u "$(DOCKER_USERNAME)" --password-stdin; \
	fi
	@docker buildx inspect "$(DOCKER_BUILDER)" >/dev/null 2>&1 || docker buildx create --name "$(DOCKER_BUILDER)"
	@docker buildx use "$(DOCKER_BUILDER)"
	@docker buildx build -t "$(DOCKER_IMAGE):$(GIT_TAG_NAME)" \
		--output "$(PUSHTAG)" \
		--platform "$(DOCKER_PLATFORMS)" \
		.

tarballs: promu
	@echo ">> building release tarballs from .build/"
	@$(PROMU) crossbuild tarballs

release: crossbuild tarballs
	@echo ">> uploading release files to github"
	@$(PROMU) release .tarballs

promu:
	@GOOS=$(UNAME_S) GOARCH=$(ARCH) $(GO) install github.com/prometheus/promu@v0.14.0
PROMU=$(shell go env GOPATH)/bin/promu

# Run go fmt against code
.PHONY: fmt
fmt:
	@find . -type f -name '*.go'| grep -v "/vendor/" | xargs gofmt -w -s

# Run mod tidy against code
.PHONY: tidy
tidy:
	@go mod tidy

# Run golang lint against code
# Enabled linters and formatters live in .golangci.yml
.PHONY: lint
lint: golangci-lint
	@$(GOLANG_LINT) run --timeout 30m

# Run gosec security checks
.PHONY: sec
sec: gosec
	@$(GOSEC) ./...

# Run staticcheck
.PHONY: staticcheck
staticcheck: staticcheck-bin
	@$(STATICCHECK) ./...

# find or download golangci-lint
# download golangci-lint if necessary
golangci-lint:
ifeq (, $(shell which golangci-lint))
	@GOOS=$(shell uname -s | tr A-Z a-z) \
    		GOARCH=$(subst x86_64,amd64,$(patsubst i%86,386,$(shell uname -m))) \
    		$(GO) install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.14.0
GOLANG_LINT=$(shell go env GOPATH)/bin/golangci-lint
else
GOLANG_LINT=$(shell which golangci-lint)
endif

# Ensure gosec is installed
gosec:
ifeq (, $(shell which gosec))
	@GOOS=$(shell uname -s | tr A-Z a-z) \
    		GOARCH=$(subst x86_64,amd64,$(patsubst i%86,386,$(shell uname -m))) \
    		$(GO) install github.com/securego/gosec/v2/cmd/gosec@latest
GOSEC=$(shell go env GOPATH)/bin/gosec
else
GOSEC=$(shell which gosec)
endif

# Ensure staticcheck is installed
staticcheck-bin:
ifeq (, $(shell which staticcheck))
	@GOOS=$(shell uname -s | tr A-Z a-z) \
    		GOARCH=$(subst x86_64,amd64,$(patsubst i%86,386,$(shell uname -m))) \
    		$(GO) install honnef.co/go/tools/cmd/staticcheck@latest
STATICCHECK=$(shell go env GOPATH)/bin/staticcheck
else
STATICCHECK=$(shell which staticcheck)
endif


.PHONY: all style format build test vet tarball tarballs docker push promu release sec staticcheck crossbuild crossbuild-docker
