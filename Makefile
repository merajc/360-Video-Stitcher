PRODUCT_NAME=360VideoStitcher
APP_NAME=360 Video Stitcher.app
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
	rm -rf "$(APP_NAME)"

.PHONY: all build run bundle install clean
