PWN_HOSTNAME := pwnagotchi
PWN_VERSION  := $(shell python3 -c "exec(open('pwnagotchi/_version.py').read()); print(__version__)")
PWN_RELEASE  := pwnagotchi-$(PWN_VERSION)-64bit
SDIST        := dist/pwnagotchi-$(PWN_VERSION).tar.gz
USER_ID      := $(shell id -u)
GROUP_ID     := $(shell id -g)

.PHONY: all clean image

all: clean image

# Merged logic to handle source distribution, sync, and the Docker build environment
image:
	@echo "--- Step 1: Creating Python source distribution ---"
	mkdir -p dist
	python3 setup.py sdist

	@echo "--- Step 2: Syncing filesystem and setting permissions ---"
	sync
	chmod +x scripts/modern_build.sh

	@echo "--- Step 3: Starting 64-bit Docker Build for $(PWN_RELEASE) ---"
	# We use --privileged to allow mounting loop devices inside the container
	sudo docker run --privileged --rm -it \
		-v /dev:/dev \
		-v /lib/modules:/lib/modules \
		-v $(shell pwd):/build \
		-w /build \
		debian:bookworm /bin/bash -c "./scripts/modern_build.sh $(PWN_VERSION) $(PWN_HOSTNAME)"

	@echo "--- Step 4: Fixing file ownership ---"
	# Docker creates files as root; this gives ownership back to the host user
	sudo chown $(USER_ID):$(GROUP_ID) dist/pwnagotchi-$(PWN_VERSION)-64bit.img

	@echo "--- SUCCESS ---"
	@echo "Build complete. Image found in dist/$(PWN_RELEASE).img"

clean:
	@echo "Cleaning up previous build artifacts..."
	-python3 setup.py clean --all
	-rm -rf dist pwnagotchi.egg-info
	-sudo rm -rf builder/output-pwnagotchi builder/packer_cache
