
export PJ_ROOT=$(PWD)

FILTER=.*

BUSTED_ARGS = \
    --lpath=$(PJ_ROOT)/lua/?.lua \
    --lpath=$(PJ_ROOT)/plenary.nvim/lua/?.lua \
    --filter=$(FILTER)

TEST_FILE = $(PJ_ROOT)/test/gitsigns_spec.lua

INIT_LUAROCKS := eval $$(luarocks --lua-version=5.1 path) &&

.DEFAULT_GOAL := build

neovim:
	git clone --depth 1 https://github.com/neovim/neovim
	make -C $@

plenary.nvim:
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim

.PHONY: test
test: neovim plenary.nvim
	make -C neovim functionaltest \
		BUSTED_ARGS="$(BUSTED_ARGS)" \
		TEST_FILE="$(TEST_FILE)"

.PHONY: tl-check
tl-check:
	$(INIT_LUAROCKS) tl check teal/**/*.tl

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
