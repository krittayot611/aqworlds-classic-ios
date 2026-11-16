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
extern void register_aot_modules(void);
extern void preload_assemblies_with_exported_symbols(void);
extern void mono_register_resources_bundle(void);

static pthread_once_t runtime_once = PTHREAD_ONCE_INIT;
static void cleanup_config(MonovmRuntimeConfigArguments *args, void *data) {
    free((void *)args->runtimeconfig.name.path);
    free(args);
}
static void initialize_once(void) {
    const char *location = getenv("AQW_MONO_BUNDLE_PATH");
    if (!location || !*location) { fprintf(stderr, "AQW Mono bundle path missing\n"); abort(); }
    register_aot_modules();
    mono_register_resources_bundle();
    const char *keys[] = {"RUNTIME_IDENTIFIER", "APP_CONTEXT_BASE_DIRECTORY"};
    const char *values[] = {"iossimulator-arm64", location};
    monovm_initialize(2, keys, values);
    size_t length = strlen(location) + sizeof("/runtimeconfig.bin");
    char *path = malloc(length);
    MonovmRuntimeConfigArguments *config = calloc(1, sizeof(*config));
    if (!path || !config) abort();
    snprintf(path, length, "%s/runtimeconfig.bin", location);
    config->kind = 0;
    config->runtimeconfig.name.path = path;
    monovm_runtimeconfig_initialize(config, cleanup_config, NULL);
    mono_set_assemblies_path(location);
    mono_jit_set_aot_mode(MONO_AOT_MODE_INTERP);
    mono_set_signal_chaining(true);
    if (!mono_jit_init("aqw.native.host")) abort();
    preload_assemblies_with_exported_symbols();
}
void aqw_runtime_init(void) { pthread_once(&runtime_once, initialize_once); }
