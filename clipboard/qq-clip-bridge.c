#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
#include <signal.h>
#include <dirent.h>
#include <sys/stat.h>
#include <wayland-client.h>
#include "wlr-data-control-unstable-v1-client-protocol.h"

static struct wl_display *display = NULL;
static struct zwlr_data_control_manager_v1 *data_control_mgr = NULL;
static struct wl_seat *seat = NULL;
static struct zwlr_data_control_device_v1 *data_device = NULL;

static struct zwlr_data_control_source_v1 *active_source = NULL;
static char *current_img_data = NULL;
static size_t current_img_size = 0;
static char current_img_mime[64] = "image/png";
static char current_img_path[512] = "";
static char richedit_str[1024] = "";
static char gnome_str[1024] = "";
static char uri_str[1024] = "";

struct pending_offer {
    struct zwlr_data_control_offer_v1 *proxy;
    char detected_image_mime[64];
    int has_image;
    int has_qq_format;
    struct pending_offer *next;
};

static struct pending_offer *offers_list = NULL;
static volatile sig_atomic_t running = 1;

static void sig_handler(int sig) {
    (void)sig;
    running = 0;
}

static void prune_cache_dir(const char *dir_path) {
    DIR *d = opendir(dir_path);
    if (!d) return;

    struct dirent *de;
    char files[128][512];
    int count = 0;

    while ((de = readdir(d)) != NULL) {
        if (de->d_name[0] == '.') continue;
        if (count < 128) {
            snprintf(files[count], sizeof(files[count]), "%s/%s", dir_path, de->d_name);
            count++;
        }
    }
    closedir(d);

    /* Keep at most 20 recent files, delete older ones */
    if (count > 20) {
        for (int i = 0; i < count - 20; i++) {
            unlink(files[i]);
        }
    }
}

static void source_send(void *data, struct zwlr_data_control_source_v1 *source,
                        const char *mime_type, int32_t fd) {
    (void)data;
    (void)source;
    fcntl(fd, F_SETFL, 0);

    if (strcmp(mime_type, "image/png") == 0 ||
        strcmp(mime_type, "image/jpeg") == 0 ||
        strcmp(mime_type, "image/webp") == 0) {
        if (current_img_data && current_img_size > 0) {
            size_t written = 0;
            while (written < current_img_size) {
                ssize_t n = write(fd, current_img_data + written, current_img_size - written);
                if (n <= 0) break;
                written += n;
            }
        }
    } else if (strcmp(mime_type, "QQ_Unicode_RichEdit_Format") == 0) {
        size_t len = strlen(richedit_str);
        ssize_t ignored = write(fd, richedit_str, len);
        (void)ignored;
    } else if (strcmp(mime_type, "x-special/gnome-copied-files") == 0) {
        size_t len = strlen(gnome_str);
        ssize_t ignored = write(fd, gnome_str, len);
        (void)ignored;
    } else if (strcmp(mime_type, "text/uri-list") == 0) {
        size_t len = strlen(uri_str);
        ssize_t ignored = write(fd, uri_str, len);
        (void)ignored;
    }
    close(fd);
}

static void source_cancelled(void *data, struct zwlr_data_control_source_v1 *source) {
    (void)data;
    if (active_source == source) {
        zwlr_data_control_source_v1_destroy(source);
        active_source = NULL;
    }
}

static const struct zwlr_data_control_source_v1_listener source_listener = {
    .send = source_send,
    .cancelled = source_cancelled,
};

static void offer_offer(void *data, struct zwlr_data_control_offer_v1 *offer, const char *mime_type) {
    (void)offer;
    struct pending_offer *po = data;
    if (strcmp(mime_type, "image/png") == 0 ||
        strcmp(mime_type, "image/jpeg") == 0 ||
        strcmp(mime_type, "image/webp") == 0) {
        po->has_image = 1;
        strncpy(po->detected_image_mime, mime_type, sizeof(po->detected_image_mime) - 1);
    } else if (strcmp(mime_type, "QQ_Unicode_RichEdit_Format") == 0) {
        po->has_qq_format = 1;
    }
}

static const struct zwlr_data_control_offer_v1_listener offer_listener = {
    .offer = offer_offer,
};

static void handle_new_image_offer(struct pending_offer *po) {
    int pfd[2];
    if (pipe2(pfd, O_CLOEXEC) < 0) {
        perror("pipe2");
        return;
    }

    const char *mime = po->detected_image_mime[0] ? po->detected_image_mime : "image/png";
    zwlr_data_control_offer_v1_receive(po->proxy, mime, pfd[1]);
    wl_display_flush(display);
    close(pfd[1]);

    size_t cap = 2 * 1024 * 1024;
    size_t size = 0;
    char *buf = malloc(cap);
    if (!buf) {
        close(pfd[0]);
        return;
    }

    while (1) {
        if (size + 65536 > cap) {
            cap *= 2;
            char *new_buf = realloc(buf, cap);
            if (!new_buf) break;
            buf = new_buf;
        }
        ssize_t n = read(pfd[0], buf + size, cap - size);
        if (n <= 0) break;
        size += n;
    }
    close(pfd[0]);

    if (size < 8) {
        free(buf);
        return;
    }

    const char *home = getenv("HOME");
    if (!home) home = "/home/clayfu";

    char cache_dir[512];
    snprintf(cache_dir, sizeof(cache_dir), "%s/.cache/qq_clipboard", home);
    mkdir(cache_dir, 0755);
    prune_cache_dir(cache_dir);

    const char *ext = "png";
    if (strcmp(mime, "image/jpeg") == 0) ext = "jpg";
    else if (strcmp(mime, "image/webp") == 0) ext = "webp";

    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    snprintf(current_img_path, sizeof(current_img_path), "%s/clip_%ld_%06ld.%s",
             cache_dir, (long)ts.tv_sec, ts.tv_nsec / 1000, ext);

    FILE *f = fopen(current_img_path, "wb");
    if (f) {
        fwrite(buf, 1, size, f);
        fclose(f);
    }

    if (current_img_data) free(current_img_data);
    current_img_data = buf;
    current_img_size = size;
    strncpy(current_img_mime, mime, sizeof(current_img_mime) - 1);

    snprintf(richedit_str, sizeof(richedit_str),
             "<QQRichEditFormat><EditElement type=\"1\" filepath=\"%s\"></EditElement></QQRichEditFormat>",
             current_img_path);
    snprintf(gnome_str, sizeof(gnome_str), "copy\nfile://%s\n", current_img_path);
    snprintf(uri_str, sizeof(uri_str), "file://%s\r\n", current_img_path);

    /* Destroy previous source if still active */
    if (active_source) {
        zwlr_data_control_source_v1_destroy(active_source);
        active_source = NULL;
    }

    struct zwlr_data_control_source_v1 *source =
        zwlr_data_control_manager_v1_create_data_source(data_control_mgr);
    zwlr_data_control_source_v1_add_listener(source, &source_listener, NULL);

    zwlr_data_control_source_v1_offer(source, current_img_mime);
    if (strcmp(current_img_mime, "image/png") != 0) {
        zwlr_data_control_source_v1_offer(source, "image/png");
    }
    zwlr_data_control_source_v1_offer(source, "QQ_Unicode_RichEdit_Format");
    zwlr_data_control_source_v1_offer(source, "x-special/gnome-copied-files");
    zwlr_data_control_source_v1_offer(source, "text/uri-list");

    active_source = source;
    zwlr_data_control_device_v1_set_selection(data_device, source);
    wl_display_flush(display);
}

static void device_data_offer(void *data, struct zwlr_data_control_device_v1 *device,
                              struct zwlr_data_control_offer_v1 *offer) {
    (void)data;
    (void)device;
    struct pending_offer *po = calloc(1, sizeof(struct pending_offer));
    po->proxy = offer;
    zwlr_data_control_offer_v1_add_listener(offer, &offer_listener, po);

    po->next = offers_list;
    offers_list = po;
}

static void device_selection(void *data, struct zwlr_data_control_device_v1 *device,
                             struct zwlr_data_control_offer_v1 *offer) {
    (void)data;
    (void)device;
    if (!offer) return;

    struct pending_offer *curr = offers_list;
    while (curr) {
        if (curr->proxy == offer) {
            if (curr->has_image && !curr->has_qq_format) {
                handle_new_image_offer(curr);
            }
            break;
        }
        curr = curr->next;
    }

    /* Clean up older offers from list */
    struct pending_offer **pp = &offers_list;
    while (*pp) {
        struct pending_offer *entry = *pp;
        if (entry->proxy != offer) {
            *pp = entry->next;
            zwlr_data_control_offer_v1_destroy(entry->proxy);
            free(entry);
        } else {
            pp = &entry->next;
        }
    }
}

static void device_finished(void *data, struct zwlr_data_control_device_v1 *device) {
    (void)data;
    (void)device;
}

static void device_primary_selection(void *data, struct zwlr_data_control_device_v1 *device,
                                     struct zwlr_data_control_offer_v1 *offer) {
    (void)data;
    (void)device;
    (void)offer;
}

static const struct zwlr_data_control_device_v1_listener device_listener = {
    .data_offer = device_data_offer,
    .selection = device_selection,
    .finished = device_finished,
    .primary_selection = device_primary_selection,
};

static void registry_handle_global(void *data, struct wl_registry *registry,
                                   uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(interface, zwlr_data_control_manager_v1_interface.name) == 0) {
        data_control_mgr = wl_registry_bind(registry, name, &zwlr_data_control_manager_v1_interface, 1);
    } else if (strcmp(interface, wl_seat_interface.name) == 0 && !seat) {
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    }
}

static void registry_handle_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_handle_global,
    .global_remove = registry_handle_global_remove,
};

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;

    signal(SIGTERM, sig_handler);
    signal(SIGINT, sig_handler);
    signal(SIGPIPE, SIG_IGN);

    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "Cannot connect to Wayland display\n");
        return 1;
    }

    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    if (!data_control_mgr || !seat) {
        fprintf(stderr, "Data control manager or seat not found\n");
        return 1;
    }

    data_device = zwlr_data_control_manager_v1_get_data_device(data_control_mgr, seat);
    zwlr_data_control_device_v1_add_listener(data_device, &device_listener, NULL);
    wl_display_roundtrip(display);

    while (running && wl_display_dispatch(display) != -1) {
    }

    if (active_source) {
        zwlr_data_control_source_v1_destroy(active_source);
    }
    if (data_device) {
        zwlr_data_control_device_v1_destroy(data_device);
    }
    if (data_control_mgr) {
        zwlr_data_control_manager_v1_destroy(data_control_mgr);
    }
    if (seat) {
        wl_seat_destroy(seat);
    }
    wl_registry_destroy(registry);
    wl_display_disconnect(display);

    if (current_img_data) {
        free(current_img_data);
    }

    return 0;
}
