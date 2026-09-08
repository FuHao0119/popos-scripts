CC = gcc
CFLAGS = -O2 -Wall
LIBS = -lwayland-client
TARGET = qq-clip-bridge
BIN_DIR = $(HOME)/.local/bin
SYSTEMD_USER_DIR = $(HOME)/.config/systemd/user

all: $(TARGET)

$(TARGET): qq-clip-bridge.c wlr-data-control-unstable-v1-protocol.c
	$(CC) $(CFLAGS) qq-clip-bridge.c wlr-data-control-unstable-v1-protocol.c $(LIBS) -o $(TARGET)

install: $(TARGET)
	install -d $(BIN_DIR)
	install -m 755 $(TARGET) $(BIN_DIR)/
	install -d $(SYSTEMD_USER_DIR)
	install -m 644 qq-clip-bridge.service $(SYSTEMD_USER_DIR)/
	systemctl --user daemon-reload
	systemctl --user enable --now qq-clip-bridge.service
	@echo "[✓] qq-clip-bridge installed and service started!"

uninstall:
	systemctl --user disable --now qq-clip-bridge.service || true
	rm -f $(SYSTEMD_USER_DIR)/qq-clip-bridge.service
	systemctl --user daemon-reload
	rm -f $(BIN_DIR)/$(TARGET)
	@echo "[✓] qq-clip-bridge uninstalled!"

clean:
	rm -f $(TARGET)

.PHONY: all install uninstall clean
