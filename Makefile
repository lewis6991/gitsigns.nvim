
export PJ_ROOT=$(PWD)

FILTER ?= .*

NVIM_RUNNER_VERSION := v0.9.1
NVIM_TEST_VERSION ?= v0.9.1

ifeq ($(shell uname -s),Darwin)
    UNAME ?= MACOS
else
    UNAME ?= LINUX
endif

NVIM_PLATFORM_MACOS := macos
NVIM_PLATFORM_LINUX := linux64
NVIM_PLATFORM ?= $(NVIM_PLATFORM_$(UNAME))

NVIM_URL := https://github.com/neovim/neovim/releases/download

NVIM_RUNNER := nvim-runner-$(NVIM_RUNNER_VERSION)
NVIM_RUNNER_URL := $(NVIM_URL)/$(NVIM_RUNNER_VERSION)/nvim-$(NVIM_PLATFORM).tar.gz

NVIM_TEST := nvim-test-$(NVIM_TEST_VERSION)
NVIM_TEST_URL := $(NVIM_URL)/$(NVIM_TEST_VERSION)/nvim-$(NVIM_PLATFORM).tar.gz

export NVIM_PRG = $(NVIM_TEST)/bin/nvim

.DEFAULT_GOAL := build

define fetch_nvim
	rm -rf $@
	rm -rf nvim-$(NVIM_PLATFORM).tar.gz
	wget $(1)
	tar -xf nvim-$(NVIM_PLATFORM).tar.gz
	rm -rf nvim-$(NVIM_PLATFORM).tar.gz
	mv nvim-$(NVIM_PLATFORM) $@
endef

$(NVIM_RUNNER):
	$(call fetch_nvim,$(NVIM_RUNNER_URL))

$(NVIM_TEST):
	$(call fetch_nvim,$(NVIM_TEST_URL))

.PHONY: nvim
nvim: $(NVIM_RUNNER) $(NVIM_TEST)

LUAROCKS := luarocks --lua-version=5.1 --tree .luarocks

.luarocks/bin/busted:
	$(LUAROCKS) install busted

.PHONY: busted
busted: .luarocks/bin/busted

.PHONY: test
test: $(NVIM_RUNNER) $(NVIM_TEST) .luarocks/bin/busted
	eval $$($(LUAROCKS) path) && $(NVIM_RUNNER)/bin/nvim -ll test/busted/runner.lua -v \
		--lazy \
		--helper=$(PWD)/test/preload.lua \
		--output test.busted.output_handler \
		--lpath=$(PWD)/lua/?.lua \
		--filter="$(FILTER)" \
		$(PWD)/test

	-@stty sane

.PHONY: test-all
test-all:
	$(MAKE) test NVIM_TEST_VERSION=v0.8.3
	$(MAKE) test NVIM_TEST_VERSION=v0.9.2
	$(MAKE) test NVIM_TEST_VERSION=nightly

.PHONY: gen_help
gen_help: $(NVIM_RUNNER)
	@$(NVIM_RUNNER)/bin/nvim -l ./gen_help.lua
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
		lua/**/*.lua lua/*.lua \
		test/*.lua test/**/*.lua

.PHONY: build
build: gen_help stylua-run

.PHONY: doc-check
doc-check: gen_help
	git diff --exit-code -- doc

