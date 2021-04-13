
export PJ_ROOT=$(PWD)

FILTER=.*

TEST_FILE = $(PJ_ROOT)/test/gitsigns_spec.lua

INIT_LUAROCKS := eval $$(luarocks --lua-version=5.1 path) &&

.DEFAULT_GOAL := build

PLATFORM := linux64

nvim-$(PLATFORM).tar.gz:
	wget https://github.com/neovim/neovim/releases/download/nightly/nvim-$(PLATFORM).tar.gz

neovim: nvim-$(PLATFORM).tar.gz
	rm -rf neovim
	tar -zxf nvim-$(PLATFORM).tar.gz
	mv nvim-$(PLATFORM) neovim
	@touch $@

plenary.nvim:
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim

export NVIM_PRG ?= neovim/bin/nvim
export NVIM_RUNTIME ?= neovim/share/nvim/runtime

.PHONY: test
test: neovim plenary.nvim
	$(INIT_LUAROCKS) busted \
		-v \
		-o test.outputHandlers.nvim \
		--lpath=$(NVIM_RUNTIME)/lua/?.lua \
		--lpath=lua/?.lua \
		--lpath=plenary.nvim/lua/?.lua \
		--filter=$(FILTER) \
		$(TEST_FILE)

.PHONY: tl-check
tl-check:
	$(INIT_LUAROCKS) tl check teal/*.tl teal/**/*.tl

.PHONY: tl-build
tl-build: tlconfig.lua
	@$(INIT_LUAROCKS) tl build
	@echo Updated lua files

.PHONY: gen_help
gen_help:
	@$(INIT_LUAROCKS) ./gen_help.lua
	@echo Updated help

.PHONY: build
build: tl-build gen_help

.PHONY: tl-ensure
tl-ensure: tl-build
	git diff --exit-code -- lua
