ZARF_VERSION ?= v0.79.0
ARCH ?= $(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
PACKAGE_VERSION ?= 0.1.0
RETROARCH_IMAGE ?= lscr.io/linuxserver/retroarch:latest

.PHONY: help lint create inspect clean

help:
	@echo "Targets:"
	@echo "  make lint    - Validate zarf.yaml against the Zarf schema"
	@echo "  make create  - Build the Zarf package for ARCH=$(ARCH)"
	@echo "  make inspect - Inspect the most recently built package"
	@echo "  make clean   - Remove built package tarballs"

lint:
	zarf dev lint . \
		--set PACKAGE_VERSION=$(PACKAGE_VERSION) \
		--set RETROARCH_IMAGE=$(RETROARCH_IMAGE)

create:
	zarf package create . \
		--confirm \
		--architecture $(ARCH) \
		--set PACKAGE_VERSION=$(PACKAGE_VERSION) \
		--set RETROARCH_IMAGE=$(RETROARCH_IMAGE)

inspect:
	@ls -1t zarf-package-retroarch-*.tar.zst 2>/dev/null | head -1 | xargs -r zarf package inspect definition

clean:
	rm -f zarf-package-retroarch-*.tar.zst
