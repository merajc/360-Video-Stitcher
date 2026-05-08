PRODUCT_NAME=GoPro360Stitcher
BUILD_DIR=.build

all: build

build:
	swift build -c release

run: build
	./$(BUILD_DIR)/release/$(PRODUCT_NAME)

bundle:
	chmod +x bundle_app.sh
	./bundle_app.sh

install:
	chmod +x bundle_app.sh
	./bundle_app.sh --install

clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(PRODUCT_NAME).app

.PHONY: all build run bundle install clean
