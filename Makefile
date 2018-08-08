.DEFAULT_GOAL=build

GOPATH?=$HOME/go
$(info $$GOPATH is [${GOPATH}])

GO_LINT_PATH := $(GOPATH)/bin/golint
GAS_PATH := $(GOPATH)/bin/gosec
WORK_DIR := ./sparta
GO_GET_FLAGS := -u

################################################################################
# Meta
################################################################################
reset:
		git reset --hard
		git clean -f -d

################################################################################
# Code generation
################################################################################
generate:
	./generate-constants.sh
	git commit -a -m "Autogenerated constants"
	@echo "Generate complete: `date`"

################################################################################
# Hygiene checks
################################################################################

GO_SOURCE_FILES := find . -type f -name '*.go' \
	! -path './vendor/*' \

.PHONY: go_get_requirements
go_get_requirements:
	go get $(GO_GET_FLAGS) honnef.co/go/tools/cmd/megacheck
	go get $(GO_GET_FLAGS) honnef.co/go/tools/cmd/gosimple
	go get $(GO_GET_FLAGS) honnef.co/go/tools/cmd/unused
	go get $(GO_GET_FLAGS) honnef.co/go/tools/cmd/staticcheck
	go get $(GO_GET_FLAGS) golang.org/x/tools/cmd/goimports
	go get $(GO_GET_FLAGS) github.com/fzipp/gocyclo
	go get $(GO_GET_FLAGS) github.com/golang/lint/golint
	go get $(GO_GET_FLAGS) github.com/mjibson/esc
	go get $(GO_GET_FLAGS) github.com/securego/gosec/cmd/gosec/...

.PHONY: update_requirements
update_requirements: GO_GET_FLAGS=-u
update_requirements: go_get_requirements
	echo "Updated tooling"

.PHONY: install_requirements
install_requirements: go_get_requirements
	echo "Installed tooling"

.PHONY: vet
vet: install_requirements
	for file in $(shell $(GO_SOURCE_FILES)); do \
		go tool vet "$${file}" || exit 1 ;\
	done

.PHONY: lint
lint: install_requirements
	for file in $(shell $(GO_SOURCE_FILES)); do \
		$(GO_LINT_PATH) "$${file}" || exit 1 ;\
	done

.PHONY: fmt
fmt: install_requirements
	$(GO_SOURCE_FILES) -exec goimports -w {} \;

.PHONY: fmtcheck
fmtcheck:install_requirements
	@ export output="$$($(GO_SOURCE_FILES) -exec goimports -d {} \;)"; \
		test -z "$${output}" || (echo "$${output}" && exit 1)

.PHONY: validate
validate: install_requirements vet lint fmtcheck
	megacheck -ignore github.com/mweagle/Sparta/CONSTANTS.go:*
	$(GAS_PATH) -exclude=G204 ./...

docs:
	@echo ""
	@echo "Sparta godocs: http://localhost:8090/pkg/github.com/mweagle/Sparta"
	@echo
	godoc -v -http=:8090 -index=true

################################################################################
# Travis
################################################################################
travis-depends: update_requirements
	go get -u github.com/golang/dep/...
	dep version
	dep ensure
	# Move everything in the ./vendor directory to the $(GOPATH)/src directory
	rsync -a --quiet --remove-source-files ./vendor/ $(GOPATH)/src


.PHONY: travis-ci-test
travis-ci-test: travis-depends test build
	go test -v -cover -race ./...

################################################################################
# Sparta commands
################################################################################
provision: build
	go run ./applications/hello_world.go --level info provision --s3Bucket $(S3_BUCKET)

execute: build
	./sparta execute

describe: build
	rm -rf ./graph.html
	go test -v -run TestDescribe

################################################################################
# ALM commands
################################################################################
.PHONY: ensure-preconditions
ensure-preconditions:
	mkdir -pv $(WORK_DIR)

.PHONY: clean
clean:
	go clean .
	go env

.PHONY: test
test: validate
	go test -v -cover -race ./...

.PHONY: test-cover
test-cover: ensure-preconditions
	go test -coverprofile=$(WORK_DIR)/cover.out -v .
	go tool cover -html=$(WORK_DIR)/cover.out
	rm $(WORK_DIR)/cover.out
	open $(WORK_DIR)/cover.html

.PHONY: build
build: validate test
	go build .
	@echo "Build complete"

.PHONY: publish
publish:
	$(info Checking Git tree status)
	git diff --exit-code
	./buildinfo.sh
	git commit -a -m "Tagging Sparta commit"
	git push origin