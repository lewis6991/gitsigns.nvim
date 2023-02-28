
export PJ_ROOT=$(PWD)

FILTER ?= .*

LUA_VERSION   := 5.1
TL_VERSION    := 0.14.1
NEOVIM_BRANCH ?= master

DEPS_DIR := $(PWD)/deps/nvim-$(NEOVIM_BRANCH)
NVIM_DIR := $(DEPS_DIR)/neovim

LUAROCKS       := luarocks --lua-version=$(LUA_VERSION)
LUAROCKS_TREE  := $(DEPS_DIR)/luarocks/usr
LUAROCKS_LPATH := $(LUAROCKS_TREE)/share/lua/$(LUA_VERSION)
LUAROCKS_INIT  := eval $$($(LUAROCKS) --tree $(LUAROCKS_TREE) path) &&

.DEFAULT_GOAL := build

$(NVIM_DIR):
	@mkdir -p $(DEPS_DIR)
	git clone --depth 1 https://github.com/neovim/neovim --branch $(NEOVIM_BRANCH) $@
	make -C $@ \
		DEPS_BUILD_DIR=$(dir $(LUAROCKS_TREE)) \
		CMAKE_BUILD_TYPE=RelWithDebInfo

TL := $(LUAROCKS_TREE)/bin/tl

$(TL):
	@mkdir -p $$(dirname $@)
	$(LUAROCKS) --tree $(LUAROCKS_TREE) install tl $(TL_VERSION)

INSPECT := $(LUAROCKS_LPATH)/inspect.lua

$(INSPECT):
	@mkdir -p $$(dirname $@)
	$(LUAROCKS) --tree $(LUAROCKS_TREE) install inspect

LUV := $(LUAROCKS_TREE)/lib/lua/$(LUA_VERSION)/luv.so

$(LUV):
	@mkdir -p $$(dirname $@)
	$(LUAROCKS) --tree $(LUAROCKS_TREE) install luv

.PHONY: lua_deps
lua_deps: $(TL) $(INSPECT)

.PHONY: test_deps
test_deps: $(NVIM_DIR)

export VIMRUNTIME=$(NVIM_DIR)/runtime
export TEST_COLORS=1

BUSTED = $$( [ -f $(NVIM_DIR)/test/busted_runner.lua ] \
        && echo "$(NVIM_DIR)/build/bin/nvim -ll $(NVIM_DIR)/test/busted_runner.lua" \
        || echo "$(LUAROCKS_INIT) busted" )

.PHONY: test
test: $(NVIM_DIR)
	$(BUSTED) -v \
		--lazy \
		--helper=$(PWD)/test/preload.lua \
		--output test.busted.outputHandlers.nvim \
		--lpath=$(NVIM_DIR)/?.lua \
		--lpath=$(NVIM_DIR)/build/?.lua \
		--lpath=$(NVIM_DIR)/runtime/lua/?.lua \
		--lpath=$(DEPS_DIR)/?.lua \
		--lpath=$(PWD)/lua/?.lua \
		--filter="$(FILTER)" \
		$(PWD)/test

	-@stty sane

.PHONY: tl-check
tl-check: $(TL)
	$(TL) check teal/*.tl teal/**/*.tl

.PHONY: tl-build
tl-build: tlconfig.lua $(TL) $(LUV)
	@$(TL) build
	@$(LUAROCKS_INIT) ./etc/add_comments.lua
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
