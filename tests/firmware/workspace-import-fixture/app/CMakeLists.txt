cmake_minimum_required(VERSION 3.20)
# No EXTRA_ZEPHYR_MODULES: the application manifest must discover the module.
find_package(Zephyr REQUIRED)
project(workspace_import_fixture)
target_sources(app PRIVATE src/main.c)
