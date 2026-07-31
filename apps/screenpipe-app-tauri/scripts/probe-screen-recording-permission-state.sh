#!/bin/bash

# screenpipe — AI that knows everything you've seen, said, or heard
# https://screenpipe.com

set -euo pipefail

if ! command -v clang >/dev/null 2>&1; then
  echo "error: clang is required; install Xcode Command Line Tools" >&2
  exit 2
fi

probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/screenpipe-tcc-probe.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT

probe_source="$probe_dir/probe.c"
probe_binary="$probe_dir/probe"

cat >"$probe_source" <<'EOF'
// screenpipe — AI that knows everything you've seen, said, or heard
// https://screenpipe.com

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

typedef uint32_t (*TCCAccessPreflightFn)(CFStringRef service);

static const char *state_name(bool cached_preflight, bool live_preflight) {
    if (!cached_preflight && !live_preflight) {
        return "denied";
    }
    if (cached_preflight && live_preflight) {
        return "granted";
    }
    if (!cached_preflight && live_preflight) {
        return "granted_needs_restart";
    }
    return "revoked_but_cached";
}

static int direct_tcc_preflight(uint32_t *result_out) {
    const char *tcc_path = "/System/Library/PrivateFrameworks/TCC.framework/TCC";
    void *tcc = dlopen(tcc_path, RTLD_LAZY | RTLD_LOCAL);
    if (tcc == NULL) {
        fprintf(stderr, "error: dlopen TCC.framework failed: %s\n", dlerror());
        return 10;
    }

    TCCAccessPreflightFn live_check =
        (TCCAccessPreflightFn)dlsym(tcc, "TCCAccessPreflight");
    const CFStringRef *screen_capture_service =
        (const CFStringRef *)dlsym(tcc, "kTCCServiceScreenCapture");

    if (live_check == NULL) {
        fprintf(stderr, "error: TCCAccessPreflight is unavailable\n");
        dlclose(tcc);
        return 11;
    }
    if (screen_capture_service == NULL || *screen_capture_service == NULL) {
        fprintf(stderr, "error: kTCCServiceScreenCapture is unavailable\n");
        dlclose(tcc);
        return 12;
    }

    *result_out = live_check(*screen_capture_service);
    dlclose(tcc);
    return 0;
}

static int fresh_process_tcc_preflight(const char *executable, uint32_t *result_out) {
    int output_pipe[2];
    if (pipe(output_pipe) != 0) {
        return 20;
    }

    posix_spawn_file_actions_t actions;
    if (posix_spawn_file_actions_init(&actions) != 0 ||
        posix_spawn_file_actions_adddup2(&actions, output_pipe[1], STDOUT_FILENO) != 0 ||
        posix_spawn_file_actions_addclose(&actions, output_pipe[0]) != 0 ||
        posix_spawn_file_actions_addclose(&actions, output_pipe[1]) != 0) {
        close(output_pipe[0]);
        close(output_pipe[1]);
        return 21;
    }

    pid_t child = 0;
    char *child_argv[] = {(char *)executable, "--fresh-tcc-preflight", NULL};
    int spawn_result = posix_spawn(&child, executable, &actions, NULL, child_argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(output_pipe[1]);
    if (spawn_result != 0) {
        close(output_pipe[0]);
        return 22;
    }

    char output[32] = {0};
    ssize_t output_length = read(output_pipe[0], output, sizeof(output) - 1);
    close(output_pipe[0]);

    int child_status = 0;
    if (waitpid(child, &child_status, 0) < 0 ||
        !WIFEXITED(child_status) || WEXITSTATUS(child_status) != 0) {
        return 23;
    }
    if (output_length <= 0 || sscanf(output, "%u", result_out) != 1) {
        return 24;
    }
    return 0;
}

int main(int argc, char **argv) {
    uint32_t live_raw = 0;
    int direct_result = direct_tcc_preflight(&live_raw);
    if (direct_result != 0) {
        return direct_result;
    }

    if (argc == 2 && strcmp(argv[1], "--fresh-tcc-preflight") == 0) {
        printf("%u\n", live_raw);
        return 0;
    }

    bool cached_preflight = CGPreflightScreenCaptureAccess();
    int fresh_result = fresh_process_tcc_preflight(argv[0], &live_raw);
    if (fresh_result != 0) {
        fprintf(stderr, "error: fresh TCC preflight failed (%d)\n", fresh_result);
        return fresh_result;
    }
    bool live_preflight = live_raw == 0;

    printf("cached_preflight=%s\n", cached_preflight ? "true" : "false");
    printf("live_preflight=%s\n", live_preflight ? "true" : "false");
    printf("live_raw=%u\n", live_raw);
    printf("state=%s\n", state_name(cached_preflight, live_preflight));

    return 0;
}
EOF

clang \
  -std=c11 \
  -Wall \
  -Wextra \
  -Werror \
  -framework CoreGraphics \
  -framework CoreFoundation \
  "$probe_source" \
  -o "$probe_binary"

echo "macos_version=$(sw_vers -productVersion)"
echo "macos_build=$(sw_vers -buildVersion)"
echo "architecture=$(uname -m)"
"$probe_binary"
