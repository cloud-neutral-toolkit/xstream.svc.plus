cmake_minimum_required(VERSION 3.22.1)

project(packet_tunnel_jni)

add_library(packet_tunnel_jni SHARED packet_tunnel_jni.cpp)

find_library(log-lib log)

target_link_libraries(packet_tunnel_jni
    ${log-lib}
)
