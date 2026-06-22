import lldb
import threading

def __lldb_init_module(debugger, internal_dict):
   pass

def register_aliases():
    lldb.debugger.HandleCommand("command script add -f common.reload_and_launch_alias r")
    lldb.debugger.HandleCommand("command script add -f common.reload_and_launch_alias run")
    lldb.debugger.HandleCommand("command script add -f common.launch_alias launch")

def initial_launch():
    threading.Thread(target=lambda: launch(lldb.debugger)).start()

def launch(debugger):
    debugger.SetAsync(True)
    debugger.HandleCommand("process launch")

def launch_alias(debugger, command, result, internal_dict):
    launch(debugger);


def reload_and_launch(debugger):
    target = debugger.GetSelectedTarget()
    if target.IsValid() and target.executable.IsValid():
        exe_path = target.executable.fullpath
        debugger.HandleCommand(f"target create '{exe_path}'")

    launch(debugger)

def reload_and_launch_alias(debugger, command, result, internal_dict):
    reload_and_launch(debugger)

