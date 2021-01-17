
export PJ_ROOT=$(PWD)

BUSTED_ARGS = \
    --lpath=$(PJ_ROOT)/lua/?.lua \
    --lpath=$(PJ_ROOT)/plenary.nvim/lua/?.lua

TEST_FILE = $(PJ_ROOT)/test/gitsigns_spec.lua

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
	eval $$(luarocks path) && tl check \
		--skip-compat53 \
		--werror all \
		-I types \
		-I teal \
		--preload types \
		teal/**/*.tl

.PHONY: tl-build
tl-build: tlconfig.lua
	eval $$(luarocks path) && tl build

.PHONY: tl-ensure
tl-ensure: tl-build
	git diff --exit-code --quiet -- lua
