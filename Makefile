
export PJ_ROOT=$(PWD)

FILTER ?= .*

export NVIM_RUNNER_VERSION := v0.9.5
export NVIM_TEST_VERSION ?= v0.9.5

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
test-all:
	$(MAKE) test NVIM_TEST_VERSION=v0.8.3
	$(MAKE) test NVIM_TEST_VERSION=v0.9.5
	$(MAKE) test NVIM_TEST_VERSION=nightly

export XDG_DATA_HOME ?= $(HOME)/.data

.PHONY: gen_help
gen_help: nvim-test
	$(XDG_DATA_HOME)/nvim-test/nvim-runner-$(NVIM_RUNNER_VERSION)/bin/nvim -l ./gen_help.lua
	@echo Updated help

STYLUA_PLATFORM_MACOS := macos-aarch64
STYLUA_PLATFORM_LINUX := linux-x86_64
STYLUA_PLATFORM := $(STYLUA_PLATFORM_$(UNAME))

STYLUA_VERSION := v0.18.2
STYLUA_ZIP := stylua-$(STYLUA_PLATFORM).zip
STYLUA_URL_BASE := https://github.com/JohnnyMorganz/StyLua/releases/download
STYLUA_URL := $(STYLUA_URL_BASE)/$(STYLUA_VERSION)/$(STYLUA_ZIP)

.INTERMEDIATE: $(STYLUA_ZIP)
$(STYLUA_ZIP):
	wget $(STYLUA_URL)

stylua: $(STYLUA_ZIP)
	unzip $<

.PHONY: stylua-check
stylua-check: stylua
	./stylua --check lua/**/*.lua

.PHONY: stylua-run
stylua-run: stylua
	./stylua \
		lua/**/*.lua \
		lua/*.lua \
		test/*.lua

.PHONY: build
build: gen_help stylua-run

.PHONY: doc-check
doc-check: gen_help
	git diff --exit-code -- doc

