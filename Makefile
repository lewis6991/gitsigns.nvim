
export PJ_ROOT=$(PWD)

FILTER ?= .*

NVIM_RUNNER_VERSION := v0.9.1
NVIM_TEST_VERSION ?= v0.9.1

ifeq ($(shell uname -s),Darwin)
    NVIM_PLATFORM ?= macos
else
    NVIM_PLATFORM ?= linux64
endif

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

.PHONY: gen_help
gen_help:
	@./gen_help.lua
	@echo Updated help

.PHONY: build
build: gen_help
