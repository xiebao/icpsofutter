cmake_minimum_required(VERSION 3.22.1)
project(native_lib)

# 设置C++标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 添加编译选项
add_compile_options(-fPIC -Wall -Wextra)

# 添加 MediaCodec 库
find_library(mediandk-lib mediandk)

# 添加 libp2p.so 库路径
set(LIBP2P_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})
set(LIBP2P_LIB ${LIBP2P_DIR}/libp2p.so)

add_library(
    native-lib
    SHARED
    native-lib.cpp
)

find_library(log-lib log)
find_library(android-lib android)

target_link_libraries(
    native-lib
    ${log-lib}
    ${android-lib}
    ${mediandk-lib}
    GLESv2
    EGL
)

# 链接 libp2p.so
if(EXISTS ${LIBP2P_LIB})
    target_link_libraries(native-lib ${LIBP2P_LIB})
    message(STATUS "Linked with libp2p.so: ${LIBP2P_LIB}")
else()
    message(WARNING "libp2p.so not found at: ${LIBP2P_LIB}")
endif()

# 设置输出目录
set_target_properties(native-lib PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}
) 