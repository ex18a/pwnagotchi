PWN_HOSTNAME := pwnagotchi
PWN_VERSION  := $(shell python3 -c "exec(open('pwnagotchi/_version.py').read()); print(__version__)")
PWN_RELEASE  := pwnagotchi-$(PWN_VERSION)-64bit
SDIST        := dist/pwnagotchi-$(PWN_VERSION).tar.gz

.PHONY: all clean image

all: clean image

# We'll merge the logic here to prevent race conditions with Docker mounts
image:
	@echo "Creating Python source distribution..."
	mkdir -p dist
	python3 setup.py sdist
	@echo "Syncing filesystem..."
	sync
	@echo "Starting 64-bit Build for $(PWN_RELEASE)..."
	sudo docker run --privileged --rm -it \
		-v /dev:/dev \
		-v /lib/modules:/lib/modules \
		-v $(shell pwd):/build \
		-w /build \
		debian:bookworm /bin/bash -c "scripts/modern_build.sh $(PWN_VERSION) $(PWN_HOSTNAME)"
	@echo "Build complete. Image found in dist/$(PWN_RELEASE).img"

clean:
	-python3 setup.py clean --all
	-rm -rf dist pwnagotchi.egg-info
	-sudo rm -rf builder/output-pwnagotchi builder/packer_cache
