#include <mpv/client.h>
#include <stdio.h>

int main(void) {
    if (mpv_client_api_version() != MPV_CLIENT_API_VERSION) {
        puts("test failed");
        return 1;
    }
    mpv_handle *handle = mpv_create();
    if (!handle) {
        puts("test failed");
        return 1;
    }
    mpv_destroy(handle);
    puts("test ok");
    return 0;
}
