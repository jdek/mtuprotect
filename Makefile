# Makefile for MTUProtect
APP_NAME = MTUProtect
BUNDLE_ID = il.luminati.mtuwatch
VERSION = 1.0

# Configuration options
AUTO_LAUNCH ?= false
VPN_INTERFACE ?= utun4
VPN_MTU ?= 1280

# Paths
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
MACOS = $(CONTENTS)/MacOS
RESOURCES = $(CONTENTS)/Resources

# Installation paths
DESTDIR ?=
INSTALL_DIR = $(DESTDIR)/Applications
DAEMON_DIR = $(DESTDIR)/Library/Application Support/MTUProtect
DAEMON_PATH = $(DAEMON_DIR)/mtuprotect-daemon
LAUNCHDAEMON_DIR = $(DESTDIR)/Library/LaunchDaemons
PLIST_PATH = $(LAUNCHDAEMON_DIR)/il.luminati.mtuprotect.plist
SOCKET_PATH = /tmp/mtuprotect.sock
LOG_PATH = /var/log/mtuprotect.log

# Compiler flags
SWIFTC = swiftc
DAEMON_FRAMEWORKS = -framework Foundation -framework SystemConfiguration
APP_FRAMEWORKS = -framework Cocoa -framework Foundation

.PHONY: all clean app daemon install uninstall install-daemon uninstall-daemon install-app uninstall-app

all: app

app: daemon
	@echo "Building $(APP_NAME).app..."
	@mkdir -p $(MACOS) $(RESOURCES)
	@$(SWIFTC) -o $(MACOS)/$(APP_NAME) mtuwatch.swift $(APP_FRAMEWORKS)
	@cp $(BUILD_DIR)/mtuprotect-daemon $(RESOURCES)/
	@echo "Creating Info.plist..."
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > $(CONTENTS)/Info.plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $(CONTENTS)/Info.plist
	@echo '<plist version="1.0">' >> $(CONTENTS)/Info.plist
	@echo '<dict>' >> $(CONTENTS)/Info.plist
	@echo '    <key>CFBundleExecutable</key>' >> $(CONTENTS)/Info.plist
	@echo '    <string>$(APP_NAME)</string>' >> $(CONTENTS)/Info.plist
	@echo '    <key>CFBundleIdentifier</key>' >> $(CONTENTS)/Info.plist
	@echo '    <string>$(BUNDLE_ID)</string>' >> $(CONTENTS)/Info.plist
	@echo '    <key>CFBundleName</key>' >> $(CONTENTS)/Info.plist
	@echo '    <string>$(APP_NAME)</string>' >> $(CONTENTS)/Info.plist
	@echo '    <key>CFBundlePackageType</key>' >> $(CONTENTS)/Info.plist
	@echo '    <string>APPL</string>' >> $(CONTENTS)/Info.plist
	@echo '    <key>CFBundleShortVersionString</key>' >> $(CONTENTS)/Info.plist
	@echo '    <string>$(VERSION)</string>' >> $(CONTENTS)/Info.plist
	@echo '    <key>CFBundleVersion</key>' >> $(CONTENTS)/Info.plist
	@echo '    <string>$(VERSION)</string>' >> $(CONTENTS)/Info.plist
	@echo '    <key>LSMinimumSystemVersion</key>' >> $(CONTENTS)/Info.plist
	@echo '    <string>10.15</string>' >> $(CONTENTS)/Info.plist
	@echo '    <key>LSUIElement</key>' >> $(CONTENTS)/Info.plist
	@echo '    <true/>' >> $(CONTENTS)/Info.plist
	@echo '    <key>NSHighResolutionCapable</key>' >> $(CONTENTS)/Info.plist
	@echo '    <true/>' >> $(CONTENTS)/Info.plist
	@echo '</dict>' >> $(CONTENTS)/Info.plist
	@echo '</plist>' >> $(CONTENTS)/Info.plist
	@echo "✓ Built: $(APP_BUNDLE)"

daemon:
	@echo "Building daemon..."
	@mkdir -p "$(BUILD_DIR)"
	@$(SWIFTC) -o $(BUILD_DIR)/mtuprotect-daemon mtuprotect.swift $(DAEMON_FRAMEWORKS)
	@echo "✓ Built: $(BUILD_DIR)/mtuprotect-daemon"

clean:
	@echo "Cleaning build directory..."
	@rm -rf $(BUILD_DIR)
	@echo "✓ Clean complete"

install: install-daemon install-app
	@echo ""
	@echo "✓ Installation complete!"
	@echo ""
	@echo "  App: $(INSTALL_DIR)/$(APP_NAME).app"
	@echo "  Daemon: $(DAEMON_PATH)"
	@echo "  LaunchDaemon: $(PLIST_PATH)"
	@echo "  Socket: $(SOCKET_PATH)"
	@echo "  Log: $(LOG_PATH)"
	@echo ""
	@echo "The daemon is running and will start automatically at boot."
	@echo "Launch the app from Applications or Spotlight."

install-daemon: daemon
	@echo "Installing daemon (requires sudo)..."
	@mkdir -p "$(DAEMON_DIR)"
	@cp $(BUILD_DIR)/mtuprotect-daemon "$(DAEMON_PATH)"
	@chmod 755 "$(DAEMON_PATH)"
	@if [ -z "$(DESTDIR)" ]; then chown root:wheel "$(DAEMON_PATH)"; fi
	@mkdir -p "$(LAUNCHDAEMON_DIR)"
	@echo "Creating LaunchDaemon plist..."
	@echo '<?xml version="1.0" encoding="UTF-8"?>' | tee "$(PLIST_PATH)" > /dev/null
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '<plist version="1.0">' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '<dict>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '    <key>Label</key>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '    <string>il.luminati.mtuprotect</string>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '    <key>ProgramArguments</key>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '    <array>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '        <string>$(DAEMON_PATH)</string>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '        <string>$(AUTO_LAUNCH)</string>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '        <string>$(VPN_INTERFACE)</string>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '        <string>$(VPN_MTU)</string>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '    </array>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '    <key>RunAtLoad</key>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '    <true/>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '    <key>KeepAlive</key>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '    <true/>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '    <key>StandardOutPath</key>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '    <string>$(LOG_PATH)</string>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '    <key>StandardErrorPath</key>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '    <string>$(LOG_PATH)</string>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '</dict>' | tee -a "$(PLIST_PATH)" > /dev/null
	@echo '</plist>' | tee -a "$(PLIST_PATH)" > /dev/null
	@chmod 644 "$(PLIST_PATH)"
	@if [ -z "$(DESTDIR)" ]; then chown root:wheel "$(PLIST_PATH)"; fi
	@if [ -z "$(DESTDIR)" ]; then launchctl unload "$(PLIST_PATH)" 2>/dev/null || true; fi
	@if [ -z "$(DESTDIR)" ]; then launchctl load "$(PLIST_PATH)"; fi
	@echo "✓ Daemon installed and started"

install-app: app
	@echo "Installing app to $(INSTALL_DIR)..."
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R $(APP_BUNDLE) "$(INSTALL_DIR)/"
	@echo "✓ App installed"

uninstall: uninstall-daemon uninstall-app
	@echo "✓ Uninstallation complete"

uninstall-daemon:
	@echo "Uninstalling daemon (requires sudo)..."
	@launchctl unload "$(PLIST_PATH)" 2>/dev/null || true
	@rm -f "$(PLIST_PATH)"
	@rm -rf "$(DAEMON_DIR)"
	@rm -f "$(SOCKET_PATH)"
	@echo "✓ Daemon uninstalled"

uninstall-app:
	@echo "Uninstalling app..."
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "✓ App uninstalled"

run: app
	@echo "Launching $(APP_NAME)..."
	@open $(APP_BUNDLE)

help:
	@echo "MTUProtect Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  make              - Build the app bundle (default)"
	@echo "  make daemon       - Build just the daemon"
	@echo "  make app          - Build the complete app bundle"
	@echo "  make clean        - Remove build directory"
	@echo "  make install      - Install both daemon and app (requires sudo)"
	@echo "  make uninstall    - Uninstall both daemon and app (requires sudo)"
	@echo "  make install-daemon   - Install just the daemon"
	@echo "  make uninstall-daemon - Uninstall just the daemon"
	@echo "  make install-app      - Install just the app"
	@echo "  make uninstall-app    - Uninstall just the app"
	@echo "  make run          - Build and launch the app"
	@echo "  make help         - Show this help"
