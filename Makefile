PRODUCT_NAME=GoPro360Stitcher
BUILD_DIR=.build

all: build

build:
	swift build -c release

run: build
	./$(BUILD_DIR)/release/$(PRODUCT_NAME)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all build run clean
