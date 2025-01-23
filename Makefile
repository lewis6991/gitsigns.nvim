
export PJ_ROOT=$(PWD)

FILTER ?= .*

export NVIM_RUNNER_VERSION := v0.10.3
export NVIM_TEST_VERSION ?= v0.10.3

ifeq ($(shell uname -s),Darwin)
    UNAME ?= MACOS
else
    UNAME ?= LINUX
endif

.DEFAULT_GOAL := build

nvim-test:
	git clone https://github.com/lewis6991/nvim-test
	nvim-test/bin/nvim-test --init

.PHONY: test
test: nvim-test
	NVIM_TEST_VERSION=$(NVIM_TEST_VERSION) \
	nvim-test/bin/nvim-test test \
		--lpath=$(PWD)/lua/?.lua \
		--verbose \
		--filter="$(FILTER)"

	-@stty sane

.PHONY: test-all
test-all: test-095 test-010 test-nightly

.PHONY: test-095
test-095:
	$(MAKE) $(MAKEFLAGS) test NVIM_TEST_VERSION=v0.9.5

.PHONY: test-010
test-010:
	$(MAKE) $(MAKEFLAGS) test NVIM_TEST_VERSION=v0.10.3

.PHONY: test-nightly
test-nightly:
	$(MAKE) $(MAKEFLAGS) test NVIM_TEST_VERSION=nightly

export XDG_DATA_HOME ?= $(HOME)/.data

NVIM := $(XDG_DATA_HOME)/nvim-test/nvim-runner-$(NVIM_RUNNER_VERSION)/bin/nvim

.PHONY: gen_help
gen_help: nvim-test
	$(NVIM) -l ./gen_help.lua
	@echo Updated help

STYLUA_PLATFORM_MACOS := macos-aarch64
STYLUA_PLATFORM_LINUX := linux-x86_64
STYLUA_PLATFORM := $(STYLUA_PLATFORM_$(UNAME))

STYLUA_VERSION := v2.0.2
STYLUA_ZIP := stylua-$(STYLUA_PLATFORM).zip
STYLUA_URL_BASE := https://github.com/JohnnyMorganz/StyLua/releases/download
STYLUA_URL := $(STYLUA_URL_BASE)/$(STYLUA_VERSION)/$(STYLUA_ZIP)

.INTERMEDIATE: $(STYLUA_ZIP)
$(STYLUA_ZIP):
	wget $(STYLUA_URL)

stylua: $(STYLUA_ZIP)
	unzip $<

LUA_FILES := $(shell git ls-files lua test)

.PHONY: stylua-check
stylua-check: stylua
	./stylua --check $(LUA_FILES)

.PHONY: stylua-run
stylua-run: stylua
	./stylua $(LUA_FILES)

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

LUALS_VERSION := 3.13.5
LUALS_TARBALL := lua-language-server-$(LUALS_VERSION)-$(shell uname -s)-$(LUALS_ARCH).tar.gz
LUALS_URL := https://github.com/LuaLS/lua-language-server/releases/download/$(LUALS_VERSION)/$(LUALS_TARBALL)

luals:
	wget $(LUALS_URL)
	mkdir luals
	tar -xf $(LUALS_TARBALL) -C luals
	rm -rf $(LUALS_TARBALL)

.PHONY: luals-check
luals-check: luals nvim-test
	VIMRUNTIME=$(XDG_DATA_HOME)/nvim-test/nvim-test-$(NVIM_TEST_VERSION)/share/nvim/runtime \
		luals/bin/lua-language-server \
			--check_out_path=check.json \
			--configpath=../.luarc.json \
			--check=lua
	cat check.json | $(NVIM) -l ./lualsreport.lua
