
export PJ_ROOT=$(PWD)

FILTER ?= .*

INIT_LUAROCKS := eval $$(luarocks --lua-version=5.1 path) &&

.DEFAULT_GOAL := build

NEOVIM_BRANCH := master

deps/neovim:
	@mkdir -p deps
	git clone --depth 1 https://github.com/neovim/neovim --branch $(NEOVIM_BRANCH) $@
	make -C $@

deps/plenary.nvim:
	@mkdir -p deps
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $@

export VIMRUNTIME=$(PWD)/deps/neovim/runtime
export TEST_COLORS=1

.PHONY: test
test: deps/neovim deps/plenary.nvim
	$(INIT_LUAROCKS) deps/neovim/.deps/usr/bin/busted \
		-v \
		--lazy \
		--helper=$(PWD)/test/preload.lua \
		--output test.busted.outputHandlers.nvim \
		--lpath=$(PWD)/deps/neovim/?.lua \
		--lpath=$(PWD)/deps/neovim/build/?.lua \
		--lpath=$(PWD)/deps/neovim/runtime/lua/?.lua \
		--lpath=$(PWD)/deps/?.lua \
		--lpath=$(PWD)/lua/?.lua \
		--lpath=$(PWD)/deps/plenary.nvim/lua/?.lua \
		--lpath=$(PWD)/deps/plenary.nvim/lua/?/init.lua \
		--filter="$(FILTER)" \
		$(PWD)/test

	-@stty sane

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
