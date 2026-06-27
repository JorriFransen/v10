import lldb
import threading

def __lldb_init_module(debugger, internal_dict):
   pass

def register_default_aliases():
    lldb.debugger.HandleCommand("command script add -f common.reload_and_launch_alias r")
    lldb.debugger.HandleCommand("command script add -f common.reload_and_launch_alias run")
    lldb.debugger.HandleCommand("command script add -f common.launch_alias launch")

cwd = "data"
def initial_launch(new_cwd):
    cwd = new_cwd
    threading.Thread(target=lambda: launch(lldb.debugger, cwd)).start()

def launch(debugger, in_cwd):
    debugger.SetAsync(True)
    debugger.HandleCommand(f"process launch -w {in_cwd}")

def launch_alias(debugger, command, result, internal_dict):
    launch(debugger, cwd);


def reload_and_launch(debugger):
    target = debugger.GetSelectedTarget()
    if target.IsValid() and target.executable.IsValid():
        exe_path = target.executable.fullpath
        debugger.HandleCommand(f"target create '{exe_path}'")

    launch(debugger, cwd)

def reload_and_launch_alias(debugger, command, result, internal_dict):
    reload_and_launch(debugger)

