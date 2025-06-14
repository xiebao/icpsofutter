cmake_minimum_required(VERSION 3.4.1)
project(native_lib)

add_library(
    native-lib
    SHARED
    native-lib.cpp
)

add_library(
    p2p
    SHARED
    IMPORTED
)
set_target_properties(
    p2p
    PROPERTIES IMPORTED_LOCATION
    ${CMAKE_SOURCE_DIR}/../jniLibs/arm64-v8a/libp2p.so
)

target_include_directories(native-lib PRIVATE ${CMAKE_SOURCE_DIR})

target_link_libraries(
    native-lib
    p2p
    log
) 