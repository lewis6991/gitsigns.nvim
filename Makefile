
all:
	luacheck lua

PJ_ROOT=$(PWD)

BUSTED_ARGS = \
    --lpath=$(PJ_ROOT)/lua/?.lua \
    --lpath=$(PJ_ROOT)/plenary.nvim/lua/?.lua

TEST_FILE = $(PJ_ROOT)/test/gitsigns_spec.lua

.PHONY: test
test:
	@git reset test/dummy.txt > /dev/null
	@[ -d plenary.nvim ] || \
		git clone --depth 1 https://github.com/nvim-lua/plenary.nvim
	@[ -d neovim ] || \
		git clone --depth 1 https://github.com/neovim/neovim
	make -C neovim functionaltest \
		BUSTED_ARGS="$(BUSTED_ARGS)" \
		TEST_FILE="$(TEST_FILE)"

