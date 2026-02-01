.PHONY: help build-docker clean clean-all compile-boot-script docker-image test-efi verify-build

DOCKER_IMAGE := cm5-kernel-builder
KERNEL_BRANCH ?= rpi-6.12.y
OUTPUT_DIR := /tmp/cm5-build-output
KERNEL_CACHE := /tmp/cm5-kernel-source

help:
	@echo "Raspberry Pi CM5 EFI Kernel Build System"
	@echo ""
	@echo "Available targets:"
	@echo "  build-docker        - Build kernel in Docker container (recommended)"
	@echo "  docker-image        - Build the Docker builder image"
	@echo "  compile-boot-script - Compile U-Boot boot script"
	@echo "  verify-build        - Verify build outputs and check for completeness"
	@echo "  test-efi            - Verify EFI binary format"
	@echo "  clean               - Clean build outputs"
	@echo "  clean-all           - Clean outputs AND kernel source cache"
	@echo ""
	@echo "Environment variables:"
	@echo "  KERNEL_BRANCH       - Kernel branch to build (default: rpi-6.12.y)"
	@echo "  OUTPUT_DIR          - Output directory (default: /tmp/cm5-build-output)"
	@echo "  KERNEL_CACHE        - Kernel source cache (default: /tmp/cm5-kernel-source)"
	@echo ""
	@echo "Typical workflow:"
	@echo "  make build-docker   - Build everything (first time: ~20-30 min)"
	@echo "  make verify-build   - Check that build succeeded"
	@echo "  ./deploy.sh ...     - Deploy to SD card (see Quick Start Guide)"
	@echo ""
	@echo "Caching:"
	@echo "  - Docker image layers are cached automatically"
	@echo "  - Kernel source is cached in $(KERNEL_CACHE)"
	@echo "  - Subsequent builds reuse cached kernel source (much faster!)"
	@echo ""
	@echo "Build outputs:"
	@echo "  $(OUTPUT_DIR)/boot/vmlinuz.efi   - EFI kernel"
	@echo "  $(OUTPUT_DIR)/dtbs/              - Device tree blobs (4 variants)"
	@echo "  $(OUTPUT_DIR)/modules/           - Kernel modules"

docker-image:
	@echo "Building Docker image: $(DOCKER_IMAGE)"
	docker build -f Dockerfile.kernel-builder -t $(DOCKER_IMAGE) .

build-docker: docker-image
	@echo "Building kernel in Docker container..."
	@echo "Output will be in: $(OUTPUT_DIR)"
	@echo "Kernel cache: $(KERNEL_CACHE)"
	@mkdir -p $(OUTPUT_DIR)
	@mkdir -p $(KERNEL_CACHE)
	docker run --rm \
		-v $(PWD):/workspace \
		-v $(OUTPUT_DIR):/build/output \
		-v $(KERNEL_CACHE):/build/linux \
		-e KERNEL_BRANCH=$(KERNEL_BRANCH) \
		-e KERNEL_SRC=/build/linux \
		$(DOCKER_IMAGE) \
		bash /workspace/build-kernel.sh
	@echo ""
	@echo "Build complete! Outputs in: $(OUTPUT_DIR)"


compile-boot-script:
	@echo "Compiling U-Boot boot script..."
	@chmod +x compile-boot-script.sh
	./compile-boot-script.sh boot-efi.cmd boot.scr
	@echo "Boot script ready: boot.scr"

test-efi:
	@echo "Verifying EFI binary format..."
	@if [ -f "$(OUTPUT_DIR)/boot/vmlinuz.efi" ]; then \
		echo "File: $(OUTPUT_DIR)/boot/vmlinuz.efi"; \
		file $(OUTPUT_DIR)/boot/vmlinuz.efi; \
		echo ""; \
		echo "Size: $$(stat -c%s $(OUTPUT_DIR)/boot/vmlinuz.efi) bytes"; \
	else \
		echo "Error: vmlinuz.efi not found in $(OUTPUT_DIR)/boot/"; \
		echo "Run 'make build-docker' first."; \
		exit 1; \
	fi

verify-build:
	@echo "Verifying build outputs..."
	@chmod +x verify-build.sh
	@./verify-build.sh $(OUTPUT_DIR)

clean:
	@echo "Cleaning build outputs..."
	rm -rf $(OUTPUT_DIR)
	rm -f boot.scr
	@echo "Clean complete."

clean-all: clean
	@echo "Cleaning kernel source cache..."
	rm -rf $(KERNEL_CACHE)
	@echo "All clean."