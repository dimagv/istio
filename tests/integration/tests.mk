#-----------------------------------------------------------------------------
# Target: test.integration.*
#-----------------------------------------------------------------------------

# The following flags (in addition to ${V}) can be specified on the command-line, or the environment. This
# is primarily used by the CI systems.

PULL_POLICY ?= Always

# $(CI) specifies that the test is running in a CI system. This enables CI specific logging.
_INTEGRATION_TEST_CIMODE_FLAG =
_INTEGRATION_TEST_PULL_POLICY = ${PULL_POLICY}
ifneq ($(CI),)
	_INTEGRATION_TEST_CIMODE_FLAG = --istio.test.ci
	_INTEGRATION_TEST_PULL_POLICY = IfNotPresent      # Using Always in CircleCI causes pull issues as images are local.
endif

# In Prow, ARTIFACTS points to the location where Prow captures the artifacts from the tests
INTEGRATION_TEST_WORKDIR =
ifneq ($(ARTIFACTS),)
	INTEGRATION_TEST_WORKDIR = ${ARTIFACTS}
endif

_INTEGRATION_TEST_INGRESS_FLAG =
ifeq (${TEST_ENV},minikube)
    _INTEGRATION_TEST_INGRESS_FLAG = --istio.test.kube.minikube
else ifeq (${TEST_ENV},minikube-none)
    _INTEGRATION_TEST_INGRESS_FLAG = --istio.test.kube.minikube
else ifeq (${TEST_ENV},kind)
    _INTEGRATION_TEST_INGRESS_FLAG = --istio.test.kube.minikube
endif


# $(INTEGRATION_TEST_WORKDIR) specifies the working directory for the tests. If not specified, then a
# temporary folder is used.
_INTEGRATION_TEST_WORKDIR_FLAG =
ifneq ($(INTEGRATION_TEST_WORKDIR),)
    _INTEGRATION_TEST_WORKDIR_FLAG = --istio.test.work_dir $(INTEGRATION_TEST_WORKDIR)
endif

# $(INTEGRATION_TEST_KUBECONFIG) specifies the kube config file to be used. If not specified, then
# ~/.kube/config is used.
# TODO: This probably needs to be more intelligent and take environment variables into account.
INTEGRATION_TEST_KUBECONFIG = ~/.kube/config
ifneq ($(KUBECONFIG),)
    INTEGRATION_TEST_KUBECONFIG = $(KUBECONFIG)
endif

# Generate integration test targets for kubernetes environment.
test.integration.%.kube: | $(JUNIT_REPORT)
	$(GO) test -p 1 ${T} ./tests/integration/$(subst .,/,$*)/... ${_INTEGRATION_TEST_WORKDIR_FLAG} ${_INTEGRATION_TEST_CIMODE_FLAG} -timeout 30m \
	--istio.test.env kube \
	--istio.test.kube.config ${INTEGRATION_TEST_KUBECONFIG} \
	--istio.test.hub=${HUB} \
	--istio.test.tag=${TAG} \
	--istio.test.pullpolicy=${_INTEGRATION_TEST_PULL_POLICY} \
	${_INTEGRATION_TEST_INGRESS_FLAG} \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

# filter out non-standard test directories
TEST_PACKAGES = $(shell go list ./tests/integration/... | grep -v /qualification | grep -v /examples | grep -v /istioio)

# Generate integration test targets for local environment.
test.integration.%.local: | $(JUNIT_REPORT)
	$(GO) test -p 1 ${T} -race ./tests/integration/$(subst .,/,$*)/... \
	--istio.test.env native \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

# Generate presubmit integration test targets for each component in kubernetes environment
test.integration.%.kube.presubmit: istioctl | $(JUNIT_REPORT)
	PATH=${PATH}:${ISTIO_OUT} $(GO) test -p 1 ${T} ./tests/integration/$(subst .,/,$*)/... ${_INTEGRATION_TEST_WORKDIR_FLAG} ${_INTEGRATION_TEST_CIMODE_FLAG} -timeout 30m \
	--istio.test.select -postsubmit,-flaky \
	--istio.test.env kube \
	--istio.test.kube.config ${INTEGRATION_TEST_KUBECONFIG} \
	--istio.test.hub=${HUB} \
	--istio.test.tag=${TAG} \
	--istio.test.pullpolicy=${_INTEGRATION_TEST_PULL_POLICY} \
	${_INTEGRATION_TEST_INGRESS_FLAG} \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

test.integration.istioio.kube.presubmit: istioctl | $(JUNIT_REPORT)
	PATH=${PATH}:${ISTIO_OUT} $(GO) test -p 1 ${T} ./tests/integration/istioio/... ${_INTEGRATION_TEST_WORKDIR_FLAG} ${_INTEGRATION_TEST_CIMODE_FLAG} -timeout 30m \
	--istio.test.select -postsubmit,-flaky \
	--istio.test.kube.operator=false \
	--istio.test.env kube \
	--istio.test.kube.config ${INTEGRATION_TEST_KUBECONFIG} \
	--istio.test.hub=${HUB} \
	--istio.test.tag=${TAG} \
	--istio.test.pullpolicy=${_INTEGRATION_TEST_PULL_POLICY} \
	${_INTEGRATION_TEST_INGRESS_FLAG} \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

test.integration.istioio.kube.postsubmit: test.integration.istioio.kube.presubmit
	SNIPPETS_GCS_PATH="istio-snippets/$(shell git rev-parse HEAD)" prow/upload-istioio-snippets.sh

# Generate presubmit integration test targets for each component in local environment.
test.integration.%.local.presubmit: | $(JUNIT_REPORT)
	$(GO) test -p 1 ${T} -race ./tests/integration/$(subst .,/,$*)/... \
	--istio.test.env native --istio.test.select -postsubmit,-flaky \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

# All integration tests targeting local environment.
.PHONY: test.integration.local
test.integration.local: | $(JUNIT_REPORT)
	$(GO) test -p 1 ${T} ${TEST_PACKAGES} --istio.test.env native \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

# Presubmit integration tests targeting local environment.
.PHONY: test.integration.local.presubmit
test.integration.local.presubmit: | $(JUNIT_REPORT)
	$(GO) test -p 1 ${T} ${TEST_PACKAGES} --istio.test.env native --istio.test.select -postsubmit,-flaky \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

# All integration tests targeting Kubernetes environment.
.PHONY: test.integration.kube
test.integration.kube: istioctl | $(JUNIT_REPORT)
	PATH=${PATH}:${ISTIO_OUT} $(GO) test -p 1 ${T} ${TEST_PACKAGES} ${_INTEGRATION_TEST_WORKDIR_FLAG} ${_INTEGRATION_TEST_CIMODE_FLAG} -timeout 30m \
	--istio.test.env kube \
	--istio.test.kube.config ${INTEGRATION_TEST_KUBECONFIG} \
	--istio.test.hub=${HUB} \
	--istio.test.tag=${TAG} \
	--istio.test.pullpolicy=${_INTEGRATION_TEST_PULL_POLICY} \
	${_INTEGRATION_TEST_INGRESS_FLAG} \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

# Presubmit integration tests targeting Kubernetes environment.
.PHONY: test.integration.kube.presubmit
test.integration.kube.presubmit: istioctl | $(JUNIT_REPORT)
	PATH=${PATH}:${ISTIO_OUT} $(GO) test -p 1 ${T} ${TEST_PACKAGES} ${_INTEGRATION_TEST_WORKDIR_FLAG} ${_INTEGRATION_TEST_CIMODE_FLAG} -timeout 30m \
    --istio.test.select -postsubmit,-flaky \
 	--istio.test.env kube \
	--istio.test.kube.config ${INTEGRATION_TEST_KUBECONFIG} \
	--istio.test.hub=${HUB} \
	--istio.test.tag=${TAG} \
	--istio.test.pullpolicy=${_INTEGRATION_TEST_PULL_POLICY} \
	${_INTEGRATION_TEST_INGRESS_FLAG} \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

# Integration tests that detect race condition for native environment.
.PHONY: test.integration.race.native
test.integration.race.native: | $(JUNIT_REPORT)
	$(GO) test -race -p 1 ${T} ${TEST_PACKAGES} -timeout 120m \
	--istio.test.env native \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

# Defines a target to run a minimal reachability testing basic traffic
.PHONY: test.integration.kube.reachability
test.integration.kube.reachability: istioctl | $(JUNIT_REPORT)
	PATH=${PATH}:${ISTIO_OUT} $(GO) test -p 1 ${T} ./tests/integration/security/ ${_INTEGRATION_TEST_WORKDIR_FLAG} ${_INTEGRATION_TEST_CIMODE_FLAG} -timeout 30m \
	--istio.test.env kube \
	--istio.test.kube.config ${INTEGRATION_TEST_KUBECONFIG} \
	--istio.test.hub=${HUB} \
	--istio.test.tag=${TAG} \
	--test.run=TestReachability \
	--istio.test.pullpolicy=${_INTEGRATION_TEST_PULL_POLICY} \
	${_INTEGRATION_TEST_INGRESS_FLAG} \
	${_INTEGRATION_TEST_INSTALL_TYPE} \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))
