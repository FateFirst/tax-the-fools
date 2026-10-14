LUA_DIR := tools/lua-5.0.3
LUA := $(LUA_DIR)/bin/lua
LUAC := $(LUA_DIR)/bin/luac
ADDON := TaxTheFools

.PHONY: test lint lua clean install media fonts

lua: $(LUA)

$(LUA):
	mkdir -p tools
	curl -sSL https://www.lua.org/ftp/lua-5.0.3.tar.gz | tar xz -C tools
	$(MAKE) -C $(LUA_DIR)

lint: $(LUA)
	LUAC=$(LUAC) sh tools/lint.sh

test: lint
	$(LUA) tests/run.lua $(wildcard tests/test_*.lua)

# Regenerate the white-mask textures the theme tints at run time.
media:
	python3 tools/make-media.py

# Download the bundled fonts (OFL) and their licences.
fonts:
	sh tools/fetch-fonts.sh

clean:
	rm -rf $(LUA_DIR)

# Copy the addon into a WoW AddOns folder: make install ADDONS=/path/to/Interface/AddOns
install:
	@test -n "$(ADDONS)" || (echo "usage: make install ADDONS=/path/to/Interface/AddOns" && exit 1)
	rm -rf "$(ADDONS)/$(ADDON)"
	cp -R $(ADDON) "$(ADDONS)/$(ADDON)"
	@echo "installed to $(ADDONS)/$(ADDON)"
