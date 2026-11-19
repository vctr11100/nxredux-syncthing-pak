PAK_NAME := $(shell jq -r .name pak.json)
PAK_TYPE := $(shell jq -r .type pak.json)
PAK_FOLDER := $(shell echo $(PAK_TYPE) | cut -c1)$(shell echo $(PAK_TYPE) | tr '[:upper:]' '[:lower:]' | cut -c2-)s

PUSH_SDCARD_PATH ?= /mnt/SDCARD
PUSH_PLATFORM ?= tg5040

ARCHITECTURES := arm64

SYNCTHING_VERSION ?= v2.1.7
# The last release of the Syncthing 1.x line. 1.x keeps its index in LevelDB
# rather than SQLite, which is why it works on the exFAT and FAT32 cards MinUI
# and NextUI require. The 1.x line is closed, so this pin is final, and
# update-syncthing.yaml follows the newest release and deliberately leaves it be.
SYNCTHING_V1_VERSION ?= v1.30.0

SYNCTHING_V1_BINS := $(foreach arch,$(ARCHITECTURES),bin/v1/$(arch)/syncthing)

clean:
	rm -f bin/*/syncthing || true
	rm -rf bin/v1 || true

build: $(foreach arch,$(ARCHITECTURES),bin/$(arch)/syncthing) $(SYNCTHING_V1_BINS)

bin/%/syncthing:
	mkdir -p bin/$*
	curl -sSL https://github.com/syncthing/syncthing/releases/download/$(SYNCTHING_VERSION)/syncthing-linux-$*-$(SYNCTHING_VERSION).tar.gz | tar -xzvf - syncthing-linux-$*-$(SYNCTHING_VERSION)/syncthing && mv syncthing-linux-$*-$(SYNCTHING_VERSION)/syncthing bin/$*/syncthing
	rm -rf syncthing-linux-$*-$(SYNCTHING_VERSION)
	chmod +x bin/$*/syncthing
	curl -f -sSL -o bin/$*/syncthing.LICENSE "https://raw.githubusercontent.com/syncthing/syncthing/refs/tags/$(SYNCTHING_VERSION)/LICENSE"

# A static pattern rule rather than a plain one, because a make stem matches
# across slashes: "bin/%/syncthing" would otherwise claim these targets with $*
# as "v1/arm" and try to fetch a 2.x build for an architecture of that name.
# Naming the targets explicitly gives this rule precedence.
$(SYNCTHING_V1_BINS): bin/v1/%/syncthing:
	mkdir -p bin/v1/$*
	curl -sSL https://github.com/syncthing/syncthing/releases/download/$(SYNCTHING_V1_VERSION)/syncthing-linux-$*-$(SYNCTHING_V1_VERSION).tar.gz | tar -xzvf - syncthing-linux-$*-$(SYNCTHING_V1_VERSION)/syncthing && mv syncthing-linux-$*-$(SYNCTHING_V1_VERSION)/syncthing bin/v1/$*/syncthing
	rm -rf syncthing-linux-$*-$(SYNCTHING_V1_VERSION)
	chmod +x bin/v1/$*/syncthing
	curl -f -sSL -o bin/v1/$*/syncthing.LICENSE "https://raw.githubusercontent.com/syncthing/syncthing/refs/tags/$(SYNCTHING_V1_VERSION)/LICENSE"

release: build
	mkdir -p dist
	git archive --format=zip --output "dist/$(PAK_NAME).pak.zip" HEAD
	while IFS= read -r file; do zip -r "dist/$(PAK_NAME).pak.zip" "$$file"; done < .gitarchiveinclude
	$(MAKE) bump-version
	zip -r "dist/$(PAK_NAME).pak.zip" pak.json
	ls -lah dist

bump-version:
	jq '.version = "$(RELEASE_VERSION)"' pak.json > pak.json.tmp
	mv pak.json.tmp pak.json

push: release
	rm -rf "dist/$(PAK_NAME).pak"
	cd dist && unzip "$(PAK_NAME).pak.zip" -d "$(PAK_NAME).pak"
	adb push "dist/$(PAK_NAME).pak/." "$(PUSH_SDCARD_PATH)/$(PAK_FOLDER)/$(PUSH_PLATFORM)/$(PAK_NAME).pak"

test:
	bats tests/

# Print the value of any make variable, e.g. `make print-SYNCTHING_VERSION`.
# update-syncthing.yaml and the bats suite read the pinned version through this.
print-%:
	@echo '$*=$($*)'
