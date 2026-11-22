// Original initializer for the experimental Mono library host.
// Compiled native exports enter once; imported script IL uses Mono's interpreter.
#include <stdbool.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mono/jit/jit.h>
#include <mono/jit/mono-private-unstable.h>
#include <mono/metadata/assembly.h>
#include <mono/metadata/mono-gc.h>
#include <mono/utils/mono-logger.h>
extern void register_aot_modules(void);
extern void preload_assemblies_with_exported_symbols(void);

static void native_note(const char *message) {
    const char *documents = getenv("AQW_MONO_DIAGNOSTICS_PATH");
    if (documents) {
        size_t length = strlen(documents) + sizeof("/runtime-progress.txt");
        char *path = malloc(length);
        if (path) {
            snprintf(path, length, "%s/runtime-progress.txt", documents);
            FILE *file = fopen(path, "a");
            if (file) { fprintf(file, "MONO_INIT %s\n", message); fclose(file); }
            free(path);
        }
    }
    fprintf(stderr, "MONO_INIT %s\n", message);
}
static void mono_log(const char *domain, const char *level, const char *message, mono_bool fatal, void *data) {
    native_note(message ? message : "Mono emitted an empty log message");
    if (fatal) exit(1);
}

static pthread_once_t runtime_once = PTHREAD_ONCE_INIT;
static void cleanup_config(MonovmRuntimeConfigArguments *args, void *data) {
    free((void *)args->runtimeconfig.name.path);
    free(args);
}
static void initialize_once(void) {
    const char *location = getenv("AQW_MONO_BUNDLE_PATH");
    if (!location || !*location) { fprintf(stderr, "AQW Mono bundle path missing\n"); abort(); }
    setenv("MONO_LOG_LEVEL", "debug", 1);
    setenv("MONO_LOG_MASK", "asm", 1);
    mono_trace_set_log_handler(mono_log, NULL);
    native_note("Registering AOT modules");
    register_aot_modules();
    native_note("Loading managed assemblies from disk (resource bundle disabled)");
    const char *keys[] = {"RUNTIME_IDENTIFIER", "APP_CONTEXT_BASE_DIRECTORY"};
    const char *values[] = {"iossimulator-arm64", location};
    size_t length = strlen(location) + sizeof("/runtimeconfig.bin");
    char *path = malloc(length);
    MonovmRuntimeConfigArguments *config = calloc(1, sizeof(*config));
    if (!path || !config) abort();
    snprintf(path, length, "%s/runtimeconfig.bin", location);
    config->kind = 0;
    config->runtimeconfig.name.path = path;
    native_note("Initializing runtime configuration");
    monovm_runtimeconfig_initialize(config, cleanup_config, NULL);
    native_note("Initializing application context");
    monovm_initialize(2, keys, values);
    mono_set_assemblies_path(location);
    mono_jit_set_aot_mode(MONO_AOT_MODE_INTERP);
    mono_set_signal_chaining(true);
    native_note("Initializing Mono domain with interpreter fallback");
    if (!mono_jit_init("aqw.native.host")) abort();
    native_note("Mono domain initialized");
    mono_gc_init_finalizer_thread();
    native_note("Finalizer thread initialized");
    preload_assemblies_with_exported_symbols();
    native_note("Export assemblies preloaded");
}
void aqw_runtime_init(void) { pthread_once(&runtime_once, initialize_once); }
