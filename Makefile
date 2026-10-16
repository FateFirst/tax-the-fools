LUA_DIR := tools/lua-5.0.3
LUA := $(LUA_DIR)/bin/lua
LUAC := $(LUA_DIR)/bin/luac
ADDON := TaxTheFools

.PHONY: test lint lua clean install media fonts recipes sync-test sync-fixture sync-build

lua: $(LUA)

$(LUA):
	mkdir -p tools
	curl -sSL https://www.lua.org/ftp/lua-5.0.3.tar.gz | tar xz -C tools
	$(MAKE) -C $(LUA_DIR)

lint: $(LUA)
	LUAC=$(LUAC) sh tools/lint.sh

test: lint
	python3 -m unittest tools/test_make_recipes.py
	$(LUA) tests/run.lua $(wildcard tests/test_*.lua)
	@if command -v go >/dev/null 2>&1; then $(MAKE) --no-print-directory sync-test; else echo "go not found: skipping sync-test"; fi

# Go tests for the sync tool.
sync-test:
	cd sync && go vet ./... && go test ./...

# Cross-compile ttf-sync for Windows and Linux (Steam Deck) into sync/dist/.
sync-build:
	mkdir -p sync/dist
	cd sync && CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -ldflags "-s -w -X main.version=1.0.0" -o dist/ttf-sync-windows-amd64.exe ./cmd/ttf-sync
	cd sync && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags "-s -w -X main.version=1.0.0" -o dist/ttf-sync-linux-amd64 ./cmd/ttf-sync

# Rebuild the SavedVariables round-trip fixture from the addon under the fake client.
sync-fixture: $(LUA)
	$(LUA) tools/sv-fixture.lua

# Regenerate the white-mask textures the theme tints at run time.
media:
	python3 tools/make-media.py

# Regenerate the built-in recipe data from the pinned LibCrafts-1.0 commit.
recipes:
	python3 tools/make-recipes.py Tailoring --out TaxTheFools/recipedata.lua

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
