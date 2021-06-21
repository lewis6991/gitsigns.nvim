
export PJ_ROOT=$(PWD)

FILTER=.*

INIT_LUAROCKS := eval $$(luarocks --lua-version=5.1 path) &&

.DEFAULT_GOAL := build

neovim:
	git clone --depth 1 https://github.com/neovim/neovim
	make -C $@

plenary.nvim:
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim

export VIMRUNTIME=$(PWD)/neovim/runtime

.PHONY: test
test: neovim plenary.nvim
	$(INIT_LUAROCKS) neovim/.deps/usr/bin/busted \
		-v \
		--lazy \
		--helper=$(PWD)/test/preload.lua \
		--output test.busted.outputHandlers.nvim \
		--lpath=$(PWD)/neovim/?.lua \
		--lpath=$(PWD)/neovim/build/?.lua \
		--lpath=$(PWD)/neovim/runtime/lua/?.lua \
		--lpath=$(PWD)/?.lua \
		--lpath=$(PWD)/lua/?.lua \
		--lpath=$(PWD)/plenary.nvim/lua/?.lua \
		--lpath=$(PWD)/plenary.nvim/lua/?/init.lua \
		--filter=$(FILTER) \
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
