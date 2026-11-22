// Original initializer for the experimental Mono library host.
// Compiled native exports enter once; imported script IL uses Mono's interpreter.
#include <stdbool.h>
#include <TargetConditionals.h>
#include <dlfcn.h>
#include <glob.h>
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
static char *trusted_assemblies;
static char pinvoke_override[2 + 2 * sizeof(void *) + 1];

// LibraryBuilder links these .NET shims into this image as static archives.
// Mono still requests them by library name when running managed wrappers.
static void *resolve_static_pinvoke(const char *library, const char *entrypoint) {
    static const char *const shims[] = {
        "System.Native", "System.Globalization.Native", "System.IO.Compression.Native",
        "System.Net.Security.Native", "System.Security.Cryptography.Native.Apple",
        "brotlienc", "brotlidec"
    };
    const char *name = strncmp(library, "lib", 3) == 0 ? library + 3 : library;
    for (size_t i = 0; i < sizeof(shims) / sizeof(shims[0]); ++i) {
        if (strcmp(name, shims[i]) == 0) return dlsym(RTLD_SELF, entrypoint);
    }
    return NULL;
}

static char *assembly_paths(const char *directory) {
    size_t pattern_length = strlen(directory) + sizeof("/*.dll");
    char *pattern = malloc(pattern_length);
    if (!pattern) abort();
    snprintf(pattern, pattern_length, "%s/*.dll", directory);
    glob_t files = {0};
    int status = glob(pattern, 0, NULL, &files);
    free(pattern);
    if (status || !files.gl_pathc) {
        native_note("No managed assembly files available for startup resolution");
        globfree(&files);
        abort();
    }
    size_t length = 1;
    for (size_t i = 0; i < files.gl_pathc; ++i) length += strlen(files.gl_pathv[i]) + 1;
    char *paths = malloc(length);
    if (!paths) abort();
    char *cursor = paths;
    for (size_t i = 0; i < files.gl_pathc; ++i) {
        if (i) *cursor++ = ':';
        size_t size = strlen(files.gl_pathv[i]);
        memcpy(cursor, files.gl_pathv[i], size);
        cursor += size;
    }
    *cursor = '\0';
    globfree(&files);
    return paths;
}
static void cleanup_config(MonovmRuntimeConfigArguments *args, void *data) {
    free((void *)args->runtimeconfig.name.path);
    free(args);
}
static void initialize_once(void) {
    const char *location = getenv("AQW_MONO_BUNDLE_PATH");
    if (!location || !*location) { fprintf(stderr, "AQW Mono bundle path missing\n"); abort(); }
    if (getenv("AQW_MONO_DIAGNOSTICS_PATH")) {
        setenv("MONO_LOG_LEVEL", "debug", 1);
        setenv("MONO_LOG_MASK", "asm", 1);
    }
    mono_trace_set_log_handler(mono_log, NULL);
    native_note("Registering AOT modules");
    register_aot_modules();
    native_note("Loading managed assemblies from disk (resource bundle disabled)");
    // CoreLib's AOT dependencies must resolve before managed AssemblyLoadContext exists.
    // Keep these paths alive for the runtime's lifetime.
    trusted_assemblies = assembly_paths(location);
    snprintf(pinvoke_override, sizeof(pinvoke_override), "%p", (void *)resolve_static_pinvoke);
    const char *keys[] = {"RUNTIME_IDENTIFIER", "APP_CONTEXT_BASE_DIRECTORY",
                          "TRUSTED_PLATFORM_ASSEMBLIES", "APP_PATHS", "NATIVE_DLL_SEARCH_DIRECTORIES",
                          "PINVOKE_OVERRIDE"};
#if TARGET_OS_SIMULATOR && defined(__x86_64__)
    const char *rid = "iossimulator-x64";
#elif TARGET_OS_SIMULATOR
    const char *rid = "iossimulator-arm64";
#else
    const char *rid = "ios-arm64";
#endif
    const char *values[] = {rid, location, trusted_assemblies, location, location,
                            pinvoke_override};
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
    monovm_initialize(sizeof(keys) / sizeof(keys[0]), keys, values);
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
