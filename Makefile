
export PJ_ROOT=$(PWD)

FILTER ?= .*

LUA_VERSION   := 5.1
TL_VERSION    := 0.14.1
NEOVIM_BRANCH := master

LUAROCKS       := luarocks --lua-version=$(LUA_VERSION)
LUAROCKS_TREE  := $(PWD)/deps/luarocks/usr
LUAROCKS_LPATH := $(LUAROCKS_TREE)/share/lua/$(LUA_VERSION)
LUAROCKS_INIT  := eval $$($(LUAROCKS) --tree $(LUAROCKS_TREE) path) &&

.DEFAULT_GOAL := build

deps/neovim:
	@mkdir -p deps
	git clone --depth 1 https://github.com/neovim/neovim --branch $(NEOVIM_BRANCH) $@
	make -C $@ DEPS_BUILD_DIR=$(dir $(LUAROCKS_TREE))

TL := $(LUAROCKS_TREE)/bin/tl

$(TL):
	@mkdir -p $@
	$(LUAROCKS) --tree $(LUAROCKS_TREE) install tl $(TL_VERSION)

INSPECT := $(LUAROCKS_LPATH)/inspect.lua

$(INSPECT):
	@mkdir -p $@
	$(LUAROCKS) --tree $(LUAROCKS_TREE) install inspect

.PHONY: lua_deps
lua_deps: $(TL) $(INSPECT)

export VIMRUNTIME=$(PWD)/deps/neovim/runtime
export TEST_COLORS=1

.PHONY: test
test: deps/neovim
	$(LUAROCKS_INIT) busted \
		-v \
		--lazy \
		--helper=$(PWD)/test/preload.lua \
		--output test.busted.outputHandlers.nvim \
		--lpath=$(PWD)/deps/neovim/?.lua \
		--lpath=$(PWD)/deps/neovim/build/?.lua \
		--lpath=$(PWD)/deps/neovim/runtime/lua/?.lua \
		--lpath=$(PWD)/deps/?.lua \
		--lpath=$(PWD)/lua/?.lua \
		--filter="$(FILTER)" \
		$(PWD)/test

	-@stty sane

.PHONY: tl-check
tl-check: $(TL)
	$(TL) check teal/*.tl teal/**/*.tl

.PHONY: tl-build
tl-build: tlconfig.lua $(TL)
	@$(TL) build
	@echo Updated lua files

.PHONY: gen_help
gen_help: $(INSPECT)
	@$(LUAROCKS_INIT) ./gen_help.lua
	@echo Updated help

.PHONY: build
build: tl-build gen_help

.PHONY: tl-ensure
tl-ensure: tl-build
	git diff --exit-code -- lua
