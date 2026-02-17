#include <jni.h>
#include <cstdint>
#include <dlfcn.h>

namespace {
using StartXrayTunnelWithFdFn = long long (*)(const char*, int32_t);
using StopXrayTunnelFn = char* (*)(long long);
using FreeXrayTunnelFn = char* (*)(long long);
using FreeCStringFn = void (*)(char*);

void* gBridgeHandle = nullptr;
StartXrayTunnelWithFdFn gStartFn = nullptr;
StopXrayTunnelFn gStopFn = nullptr;
FreeXrayTunnelFn gFreeFn = nullptr;
FreeCStringFn gFreeCStringFn = nullptr;

bool ensureBridgeLoaded() {
    if (gStartFn != nullptr && gStopFn != nullptr && gFreeFn != nullptr && gFreeCStringFn != nullptr) {
        return true;
    }
    if (gBridgeHandle == nullptr) {
        gBridgeHandle = dlopen("libgo_native_bridge.so", RTLD_NOW);
    }
    if (gBridgeHandle == nullptr) {
        return false;
    }

    gStartFn = reinterpret_cast<StartXrayTunnelWithFdFn>(dlsym(gBridgeHandle, "StartXrayTunnelWithFd"));
    gStopFn = reinterpret_cast<StopXrayTunnelFn>(dlsym(gBridgeHandle, "StopXrayTunnel"));
    gFreeFn = reinterpret_cast<FreeXrayTunnelFn>(dlsym(gBridgeHandle, "FreeXrayTunnel"));
    gFreeCStringFn = reinterpret_cast<FreeCStringFn>(dlsym(gBridgeHandle, "FreeCString"));

    return gStartFn != nullptr && gStopFn != nullptr && gFreeFn != nullptr && gFreeCStringFn != nullptr;
}

jstring toJStringAndFree(JNIEnv* env, char* ptr) {
    if (ptr == nullptr) {
        return env->NewStringUTF("error:null_response");
    }
    jstring out = env->NewStringUTF(ptr);
    if (gFreeCStringFn != nullptr) {
        gFreeCStringFn(ptr);
    }
    return out;
}
}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_example_xstream_NativePacketTunnelBridge_nativeStartTunnel(
    JNIEnv* env,
    jobject /* thiz */,
    jstring configJson,
    jint tunFd
) {
    if (configJson == nullptr || tunFd <= 0 || !ensureBridgeLoaded()) {
        return static_cast<jlong>(-1);
    }

    const char* configChars = env->GetStringUTFChars(configJson, nullptr);
    if (configChars == nullptr) {
        return static_cast<jlong>(-1);
    }

    const jlong handle = static_cast<jlong>(
        gStartFn(configChars, static_cast<int32_t>(tunFd))
    );
    env->ReleaseStringUTFChars(configJson, configChars);
    return handle;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_xstream_NativePacketTunnelBridge_nativeStopTunnel(
    JNIEnv* env,
    jobject /* thiz */,
    jlong handle
) {
    if (handle <= 0) {
        return env->NewStringUTF("error:invalid_handle");
    }
    if (!ensureBridgeLoaded()) {
        return env->NewStringUTF("error:native_bridge_unavailable");
    }
    char* result = gStopFn(static_cast<long long>(handle));
    return toJStringAndFree(env, result);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_xstream_NativePacketTunnelBridge_nativeFreeTunnel(
    JNIEnv* env,
    jobject /* thiz */,
    jlong handle
) {
    if (handle <= 0) {
        return env->NewStringUTF("error:invalid_handle");
    }
    if (!ensureBridgeLoaded()) {
        return env->NewStringUTF("error:native_bridge_unavailable");
    }
    char* result = gFreeFn(static_cast<long long>(handle));
    return toJStringAndFree(env, result);
}
