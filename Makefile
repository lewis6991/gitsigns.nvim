
export PJ_ROOT=$(PWD)

FILTER ?= .*

export NVIM_RUNNER_VERSION := v0.11.0
export NVIM_TEST_VERSION ?= v0.11.0

ifeq ($(shell uname -s),Darwin)
    UNAME ?= MACOS
else
    UNAME ?= LINUX
endif

.DEFAULT_GOAL := build

NVIM_TEST := deps/nvim-test

.PHONY: nvim-test
nvim-test: $(NVIM_TEST)

$(NVIM_TEST):
	git clone --depth 1 --branch v1.1.1 https://github.com/lewis6991/nvim-test $@
	$@/bin/nvim-test --init

.PHONY: test
test: $(NVIM_TEST)
	NVIM_TEST_VERSION=$(NVIM_TEST_VERSION) \
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

export XDG_DATA_HOME ?= $(HOME)/.data

NVIM := $(XDG_DATA_HOME)/nvim-test/nvim-runner-$(NVIM_RUNNER_VERSION)/bin/nvim

.PHONY: gen_help
gen_help: $(NVIM_TEST)
	$(NVIM) -l ./gen_help.lua
	@echo Updated help

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

.PHONY: build
build: gen_help stylua-run

.PHONY: doc-check
doc-check: gen_help
	git diff --exit-code -- doc

ifeq ($(shell uname -m),arm64)
    LUALS_ARCH ?= arm64
else
    LUALS_ARCH ?= x64
endif

LUALS_VERSION := 3.13.9
LUALS := deps/lua-language-server-$(LUALS_VERSION)-$(shell uname -s)-$(LUALS_ARCH)
LUALS_TARBALL := $(LUALS).tar.gz
LUALS_URL := https://github.com/LuaLS/lua-language-server/releases/download/$(LUALS_VERSION)/$(notdir $(LUALS_TARBALL))

.PHONY: luals
luals: $(LUALS)

$(LUALS):
	wget --directory-prefix=$(dir $@) $(LUALS_URL)
	mkdir -p $@
	tar -xf $(LUALS_TARBALL) -C $@
	rm -rf $(LUALS_TARBALL)

.PHONY: luals-check
luals-check: $(LUALS) $(NVIM_TEST)
	VIMRUNTIME=$(XDG_DATA_HOME)/nvim-test/nvim-test-$(NVIM_TEST_VERSION)/share/nvim/runtime \
		$(LUALS)/bin/lua-language-server \
			--configpath=../.luarc.json \
			--check=lua
