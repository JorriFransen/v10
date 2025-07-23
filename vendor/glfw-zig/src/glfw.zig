/////////////
// IMPORTANT: This is a subset
// /////////

const std = @import("std");
const builtin = @import("builtin");

pub const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

const vk = @import("vulkan");

pub const CLIENT_API: c_int = c.GLFW_CLIENT_API;
pub const RESIZABLE: c_int = c.GLFW_RESIZABLE;
pub const WAYLAND_APP_ID = c.GLFW_WAYLAND_APP_ID;
pub const PLATFORM = c.GLFW_PLATFORM;

pub const NO_API: c_int = c.GLFW_NO_API;

pub const TRUE = c.GLFW_TRUE;
pub const FALSE = c.GLFW_FALSE;

pub const Window = ?*c.GLFWwindow;
pub const Monitor = ?*c.GLFWmonitor;

inline fn f(comptime name: []const u8, comptime T: type) *const T {
    return @extern(*const T, .{ .name = name });
}

pub const init = f("glfwInit", fn () callconv(.c) c_int);
pub const initHint = f("glfwInitHint", fn (hint: c_int, value: c_int) callconv(.c) void);
pub const getError = f("glfwGetError", fn (description: ?*const [*:0]const u8) callconv(.c) c_int);
pub const windowHint = f("glfwWindowHint", fn (hint: c_int, value: c_int) callconv(.c) void);
pub const windowHintString = f("glfwWindowHintString", fn (hint: c_int, value: [*:0]const u8) callconv(.c) void);
pub const createWindow = f("glfwCreateWindow", fn (width: c_int, height: c_int, title: [*:0]const u8, monitor: ?*Monitor, share: Window) callconv(.c) Window);
pub const windowShouldClose = f("glfwWindowShouldClose", fn (window: Window) callconv(.c) c_int);
pub const setWindowShouldClose = f("glfwSetWindowShouldClose", fn (window: Window, value: c_int) callconv(.c) void);
pub const pollEvents = f("glfwPollEvents", fn () callconv(.c) void);
pub const waitEvents = f("glfwWaitEvents", fn () callconv(.c) void);
pub const setKeyCallback = f("glfwSetKeyCallback", fn (window: Window, callback: GLFWkeyfun) callconv(.c) GLFWkeyfun);
pub const setFramebufferSizeCallback = f("glfwSetFramebufferSizeCallback", fn (window: Window, callback: GLFWframebuffersizefun) callconv(.c) GLFWframebuffersizefun);
pub const setWindowRefreshCallback = f("glfwSetWindowRefreshCallback", fn (window: Window, callback: GLFWwindowrefreshfun) callconv(.c) GLFWwindowrefreshfun);
pub const setWindowSizeCallback = f("glfwSetWindowSizeCallback", fn (window: Window, callback: GLFWwindowsizefun) callconv(.c) GLFWwindowsizefun);
pub const destroyWindow = f("glfwDestroyWindow", fn (window: Window) callconv(.c) void);
pub const terminate = f("glfwTerminate", fn () callconv(.c) void);
pub const getFramebufferSize = f("glfwGetFramebufferSize", fn (window: ?*const c.GLFWwindow, width: ?*c_int, height: ?*c_int) callconv(.c) void);
pub const swapBuffers = f("glfwSwapBuffers", fn (window: ?*const c.GLFWwindow) callconv(.c) void);
pub const getKey = f("glfwGetKey", fn (window: ?*const c.GLFWwindow, key: c_int) callconv(.c) c_int);

pub const platformSupported = f("glfwPlatformSupported", fn (platform: Platform) callconv(.c) c_int);
pub const getPlatform = f("glfwGetPlatform", fn () callconv(.c) Platform);
pub const vulkanSupported = f("glfwVulkanSupported", fn () callconv(.c) c_int);
pub const getRequiredInstanceExtensions = f("glfwGetRequiredInstanceExtensions", fn (count: *u32) callconv(.c) ?[*][*:0]const u8);
pub const setWindowUserPointer = f("glfwSetWindowUserPointer", fn (window: Window, ptr: *anyopaque) callconv(.c) void);
pub const getWindowUserPointer = f("glfwGetWindowUserPointer", fn (window: Window) callconv(.c) *anyopaque);

pub const getInstanceProcAddress = f("glfwGetInstanceProcAddress", fn (instance: vk.Instance, proc_name: [*:0]const u8) callconv(vk.vulkan_call_conv) vk.PfnVoidFunction);
pub const createWindowSurface = f("glfwCreateWindowSurface", fn (instance: vk.Instance, window: *c.GLFWwindow, allocator: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) callconv(.c) vk.Result);

pub const GLFWkeyfun = *const fn (window: Window, key: c_int, scancode: c_int, action: Action, mods: c_int) callconv(.c) void;
pub const GLFWframebuffersizefun = *const fn (window: Window, width: c_int, height: c_int) callconv(.c) void;
pub const GLFWwindowrefreshfun = *const fn (window: Window) callconv(.c) void;
pub const GLFWwindowsizefun = *const fn (window: Window, width: c_int, height: c_int) callconv(.c) void;

pub const Platform = enum(c_int) {
    ANY = 0x00060000,
    WIN32 = 0x00060001,
    COCOA = 0x00060002,
    WAYLAND = 0x00060003,
    X11 = 0x00060004,
    NULL = 0x00060005,
};

pub const Action = enum(c_int) {
    release = 0,
    press = 1,
    repeat = 2,
};
