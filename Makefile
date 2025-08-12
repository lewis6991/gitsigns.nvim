export XDG_DATA_HOME ?= $(HOME)/.data
export PJ_ROOT=$(PWD)

ifeq ($(shell uname -s),Darwin)
    UNAME ?= MACOS
else
    UNAME ?= LINUX
endif

.DEFAULT_GOAL := build

.PHONY: build
build: doc stylua-run

################################################################################
# nvim-test
################################################################################

export NVIM_RUNNER_VERSION := v0.11.0
export NVIM_TEST_VERSION ?= v0.11.0

NVIM_TEST := deps/nvim-test

.PHONY: nvim-test
nvim-test: $(NVIM_TEST)

$(NVIM_TEST):
	git clone --depth 1 --branch v1.2.0 https://github.com/lewis6991/nvim-test $@
	$@/bin/nvim-test --init

################################################################################
# Testsuite
################################################################################

FILTER ?= .*

.PHONY: test
test: $(NVIM_TEST)
	$(NVIM_TEST)/bin/nvim-test test \
		--lpath=$(PWD)/lua/?.lua \
		--verbose \
		--filter="$(FILTER)"

	-@stty sane

.PHONY: test-all
test-all: test-095 test-010 test-nightly

.PHONY: test-010
test-010:
	$(MAKE) $(MAKEFLAGS) test NVIM_TEST_VERSION=v0.10.4

.PHONY: test-011
test-011:
	$(MAKE) $(MAKEFLAGS) test NVIM_TEST_VERSION=v0.11.0

.PHONY: test-nightly
test-nightly:
	$(MAKE) $(MAKEFLAGS) test NVIM_TEST_VERSION=nightly

NVIM := $(XDG_DATA_HOME)/nvim-test/nvim-runner-$(NVIM_RUNNER_VERSION)/bin/nvim

################################################################################
# Docs
################################################################################

.PHONY: doc
doc: $(NVIM_TEST)
	$(NVIM) -l ./gen_help.lua
	@echo Updated help

.PHONY: doc-check
doc-check: doc
	git diff --exit-code -- doc

################################################################################
# Stylua
################################################################################

STYLUA_PLATFORM_MACOS := macos-aarch64
STYLUA_PLATFORM_LINUX := linux-x86_64
STYLUA_PLATFORM := $(STYLUA_PLATFORM_$(UNAME))

STYLUA_VERSION := v2.0.2
STYLUA_ZIP := stylua-$(STYLUA_PLATFORM).zip
STYLUA_URL_BASE := https://github.com/JohnnyMorganz/StyLua/releases/download
STYLUA_URL := $(STYLUA_URL_BASE)/$(STYLUA_VERSION)/$(STYLUA_ZIP)
STYLUA := deps/stylua

.INTERMEDIATE: $(STYLUA_ZIP)
$(STYLUA_ZIP):
	wget $(STYLUA_URL)

.PHONY: stylua
stylua: $(STYLUA)

$(STYLUA): $(STYLUA_ZIP)
	unzip $< -d $(dir $@)

LUA_FILES := $(shell git ls-files lua test)

.PHONY: stylua-check
stylua-check: $(STYLUA)
	$(STYLUA) --check $(LUA_FILES)

.PHONY: stylua-run
stylua-run: $(STYLUA)
	$(STYLUA) $(LUA_FILES)

################################################################################
# Emmylua
################################################################################

ifeq ($(shell uname -m),arm64)
    EMMYLUA_ARCH ?= arm64
else
    EMMYLUA_ARCH ?= x64
endif

EMMYLUA_REF := 0.11.0
EMMYLUA_OS ?= $(shell uname -s | tr '[:upper:]' '[:lower:]')
EMMYLUA_RELEASE_URL := https://github.com/EmmyLuaLs/emmylua-analyzer-rust/releases/download/$(EMMYLUA_REF)/emmylua_check-$(EMMYLUA_OS)-$(EMMYLUA_ARCH).tar.gz
EMMYLUA_RELEASE_TAR := deps/emmylua_check-$(EMMYLUA_REF)-$(EMMYLUA_OS)-$(EMMYLUA_ARCH).tar.gz
EMMYLUA_DIR := deps/emmylua
EMMYLUA_BIN := $(EMMYLUA_DIR)/emmylua_check

.PHONY: emmylua
emmylua: $(EMMYLUA_BIN)

ifeq ($(shell echo $(EMMYLUA_REF) | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$$'),$(EMMYLUA_REF))

$(EMMYLUA_BIN):
	mkdir -p $(EMMYLUA_DIR)
	curl -L $(EMMYLUA_RELEASE_URL) -o $(EMMYLUA_RELEASE_TAR)
	tar -xzf $(EMMYLUA_RELEASE_TAR) -C $(EMMYLUA_DIR)

else

$(EMMYLUA_BIN):
	git clone --filter=blob:none https://github.com/EmmyLuaLs/emmylua-analyzer-rust.git $(EMMYLUA_DIR)
	git -C $(EMMYLUA_DIR) checkout $(EMMYLUA_SHA)
	cd $(EMMYLUA_DIR) && cargo build --release --package emmylua_check

endif

NVIM_TEST_RUNTIME=$(XDG_DATA_HOME)/nvim-test/nvim-test-$(NVIM_TEST_VERSION)/share/nvim/runtime

$(NVIM_TEST_RUNTIME): $(NVIM_TEST)
	$^/bin/nvim-test --init

.PHONY: emmylua-check
emmylua-check: $(EMMYLUA_BIN) $(NVIM_TEST_RUNTIME)
	VIMRUNTIME=$(NVIM_TEST_RUNTIME) \
		$(EMMYLUA_BIN) . \
		--ignore 'test/**/*' \
		--ignore gen_help.lua
