cmake_minimum_required(VERSION 3.4.1)
project(native_lib)

add_library(
    native-lib
    SHARED
    native-lib.cpp
)

# 根据目标架构选择正确的so库路径
if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(P2P_LIB_PATH ${CMAKE_SOURCE_DIR}/../jniLibs/arm64-v8a/libp2p.so)
    target_compile_definitions(native-lib PRIVATE ANDROID_ABI_arm64_v8a)
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    set(P2P_LIB_PATH ${CMAKE_SOURCE_DIR}/../jniLibs/armeabi-v7a/libp2p.so)
else()
    message(FATAL_ERROR "Unsupported ABI: ${ANDROID_ABI}")
endif()

add_library(
    p2p
    SHARED
    IMPORTED
)
set_target_properties(
    p2p
    PROPERTIES IMPORTED_LOCATION
    ${P2P_LIB_PATH}
)

target_include_directories(native-lib PRIVATE ${CMAKE_SOURCE_DIR})

find_library(log-lib log)
find_library(android-lib android)

add_library(
    cjson
    STATIC
    cJSON.c
)

target_link_libraries(
    native-lib
    cjson
    ${log-lib}
    ${android-lib}
    p2p
) 