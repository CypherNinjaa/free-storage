#include <jni.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <android/log.h>

#define LOG_TAG "KeepsakeTdBridge"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

typedef int (*td_create_client_id_fn)(void);
typedef void (*td_send_fn)(int client_id, const char *request);
typedef const char *(*td_receive_fn)(double timeout);
typedef const char *(*td_execute_fn)(const char *request);

static pthread_once_t g_once = PTHREAD_ONCE_INIT;
static int g_ready = 0;
static td_create_client_id_fn g_create_client_id = NULL;
static td_send_fn g_send = NULL;
static td_receive_fn g_receive = NULL;
static td_execute_fn g_execute = NULL;

static void load_tdjson(void) {
    void *lib = dlopen("libtdjson.so", RTLD_NOW | RTLD_GLOBAL);
    if (lib == NULL) {
        LOGE("dlopen(libtdjson.so) failed: %s", dlerror());
        return;
    }
    g_create_client_id = (td_create_client_id_fn) dlsym(lib, "td_create_client_id");
    g_send = (td_send_fn) dlsym(lib, "td_send");
    g_receive = (td_receive_fn) dlsym(lib, "td_receive");
    g_execute = (td_execute_fn) dlsym(lib, "td_execute");
    if (g_create_client_id == NULL || g_send == NULL || g_receive == NULL || g_execute == NULL) {
        LOGE("libtdjson.so is missing one of td_create_client_id/td_send/td_receive/td_execute");
        return;
    }
    g_ready = 1;
}

static int ensure_loaded(void) {
    pthread_once(&g_once, load_tdjson);
    return g_ready;
}

static char *copy_to_c_string(JNIEnv *env, jbyteArray bytes) {
    jsize length = (*env)->GetArrayLength(env, bytes);
    char *buffer = malloc((size_t) length + 1);
    if (buffer == NULL) return NULL;
    (*env)->GetByteArrayRegion(env, bytes, 0, length, (jbyte *) buffer);
    buffer[length] = '\0';
    return buffer;
}

static jbyteArray to_byte_array(JNIEnv *env, const char *value) {
    size_t length = strlen(value);
    jbyteArray result = (*env)->NewByteArray(env, (jsize) length);
    if (result == NULL) return NULL;
    (*env)->SetByteArrayRegion(env, result, 0, (jsize) length, (const jbyte *) value);
    return result;
}

JNIEXPORT jint JNICALL
Java_app_alextran_immich_keepsake_TdJsonBridge_nativeCreateClientId(JNIEnv *env, jobject thiz) {
    if (!ensure_loaded()) return -1;
    return (jint) g_create_client_id();
}

JNIEXPORT void JNICALL
Java_app_alextran_immich_keepsake_TdJsonBridge_nativeSend(JNIEnv *env, jobject thiz, jint client_id, jbyteArray request) {
    if (!ensure_loaded() || request == NULL) return;
    char *buffer = copy_to_c_string(env, request);
    if (buffer == NULL) return;
    g_send((int) client_id, buffer);
    free(buffer);
}

JNIEXPORT jbyteArray JNICALL
Java_app_alextran_immich_keepsake_TdJsonBridge_nativeReceive(JNIEnv *env, jobject thiz, jdouble timeout) {
    if (!ensure_loaded()) return NULL;
    const char *response = g_receive((double) timeout);
    if (response == NULL) return NULL;
    return to_byte_array(env, response);
}

JNIEXPORT jbyteArray JNICALL
Java_app_alextran_immich_keepsake_TdJsonBridge_nativeExecute(JNIEnv *env, jobject thiz, jbyteArray request) {
    if (!ensure_loaded() || request == NULL) return NULL;
    char *buffer = copy_to_c_string(env, request);
    if (buffer == NULL) return NULL;
    const char *response = g_execute(buffer);
    free(buffer);
    if (response == NULL) return NULL;
    return to_byte_array(env, response);
}
