cmake_minimum_required(VERSION 3.22.1)
project(keepsake_tdbridge C)

add_library(keepsake_tdbridge SHARED td_bridge.c)

find_library(log-lib log)
target_link_libraries(keepsake_tdbridge ${log-lib} dl)
