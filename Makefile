# GCal Access - build helper. Run `make help`.
APP      := gcal_access
FLUTTER  ?= flutter
ARCH     := $(shell uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')
BUNDLE   := build/linux/$(ARCH)/release/bundle
DIST_DIR := dist
PKG      := $(APP)-linux-$(ARCH)
PKG_DIR  := $(DIST_DIR)/$(PKG)

.PHONY: help deps analyze test check build dist run clean

help:
	@echo "make deps     - fetch Dart/Flutter packages"
	@echo "make check    - analyze + test"
	@echo "make build    - release build of the Linux bundle ($(BUNDLE))"
	@echo "make dist     - self-contained tarball: $(DIST_DIR)/$(PKG).tar.gz"
	@echo "make run      - run the app in debug mode"
	@echo "make clean    - remove build/ and dist/"

deps:
	$(FLUTTER) pub get

analyze: deps
	$(FLUTTER) analyze

test: deps
	$(FLUTTER) test

check: analyze test

build: deps
	$(FLUTTER) build linux --release

# The bundle (executable + lib/ + data/) is relocatable. Only keys/KEY.md is
# shipped - never credentials; the user adds their own JSON to keys/.
dist: build
	rm -rf $(PKG_DIR)
	mkdir -p $(PKG_DIR)/keys
	cp -a $(BUNDLE)/. $(PKG_DIR)/
	cp keys/KEY.md $(PKG_DIR)/keys/KEY.md
	tar -C $(DIST_DIR) -czf $(DIST_DIR)/$(PKG).tar.gz $(PKG)
	cd $(DIST_DIR) && sha256sum $(PKG).tar.gz > $(PKG).tar.gz.sha256
	@echo "Built $(DIST_DIR)/$(PKG).tar.gz"

run: deps
	$(FLUTTER) run -d linux

clean:
	$(FLUTTER) clean
	rm -rf $(DIST_DIR)
