export XDG_DATA_HOME ?= $(HOME)/.data
export PJ_ROOT=$(PWD)

ifeq ($(shell uname -s),Darwin)
    UNAME ?= MACOS
else
    UNAME ?= LINUX
endif

MAKEFLAGS += --no-builtin-rules
MAKEARGS += --warn-undefined-variables

.DEFAULT_GOAL := build

.PHONY: build
build: doc format

################################################################################
# nvim-test
################################################################################

export NVIM_RUNNER_VERSION := v0.11.0
export NVIM_TEST_VERSION ?= v0.11.0

NVIM_TEST := deps/nvim-test

.PHONY: nvim-test
nvim-test: $(NVIM_TEST)

$(NVIM_TEST):
	git clone --depth 1 --branch v1.3.0 https://github.com/lewis6991/nvim-test $@
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

.PHONY: format-check
format-check: $(STYLUA)
	$(STYLUA) --check $(LUA_FILES)

.PHONY: format
format: $(STYLUA)
	$(STYLUA) $(LUA_FILES)

################################################################################
# Emmylua
################################################################################

ifeq ($(shell uname -m),arm64)
    EMMYLUA_ARCH ?= arm64
else
    EMMYLUA_ARCH ?= x64
endif

EMMYLUA_REF := 0.19.0
EMMYLUA_OS ?= $(shell uname -s | tr '[:upper:]' '[:lower:]')

EMMYLUA_RELEASE_URL_BASE := https://github.com/EmmyLuaLs/emmylua-analyzer-rust/releases/download/$(EMMYLUA_REF)
EMMYLUA_DIR := deps/emmylua-$(EMMYLUA_REF)

EMMYLUA_RELEASE_URL := $(EMMYLUA_RELEASE_URL_BASE)/emmylua_check-$(EMMYLUA_OS)-$(EMMYLUA_ARCH).tar.gz
EMMYLUA_RELEASE_TAR := deps/emmylua_check-$(EMMYLUA_REF)-$(EMMYLUA_OS)-$(EMMYLUA_ARCH).tar.gz
EMMYLUA_BIN := $(EMMYLUA_DIR)/emmylua_check

EMMYLUADOC_RELEASE_URL := $(EMMYLUA_RELEASE_URL_BASE)/emmylua_doc_cli-$(EMMYLUA_OS)-$(EMMYLUA_ARCH).tar.gz
EMMYLUADOC_RELEASE_TAR := deps/emmylua_doc-$(EMMYLUA_REF)-$(EMMYLUA_OS)-$(EMMYLUA_ARCH).tar.gz
EMMYLUADOC_BIN := $(EMMYLUA_DIR)/emmylua_doc_cli

.PHONY: emmylua
emmylua: $(EMMYLUA_BIN)

$(EMMYLUA_BIN):
	mkdir -p $(EMMYLUA_DIR)
	curl -L $(EMMYLUA_RELEASE_URL) -o $(EMMYLUA_RELEASE_TAR)
	tar -xzf $(EMMYLUA_RELEASE_TAR) -C $(EMMYLUA_DIR)

$(EMMYLUADOC_BIN):
	mkdir -p $(EMMYLUA_DIR)
	curl -L $(EMMYLUADOC_RELEASE_URL) -o $(EMMYLUADOC_RELEASE_TAR)
	tar -xzf $(EMMYLUADOC_RELEASE_TAR) -C $(EMMYLUA_DIR)

NVIM_TEST_RUNTIME=$(XDG_DATA_HOME)/nvim-test/nvim-test-$(NVIM_TEST_VERSION)/share/nvim/runtime

$(NVIM_TEST_RUNTIME): $(NVIM_TEST)
	$^/bin/nvim-test --init

################################################################################
# Type check
################################################################################

.PHONY: emmylua-check
emmylua-check: $(EMMYLUA_BIN) $(NVIM_TEST_RUNTIME)
	VIMRUNTIME=$(NVIM_TEST_RUNTIME) \
		$(EMMYLUA_BIN) . \
		--ignore 'test/**/*' \
		--ignore gen_help.lua

################################################################################
# Docs
################################################################################

.PHONY: doc

doc: $(NVIM_TEST) $(NVIM_TEST_RUNTIME) $(EMMYLUADOC_BIN)
	VIMRUNTIME=$(NVIM_TEST_RUNTIME) \
		$(EMMYLUADOC_BIN) lua --output emydoc --output-format json
	$(NVIM) -l ./gen_help.lua
	@echo Updated help

.PHONY: doc-check
doc-check: doc
	git diff --exit-code -- doc

