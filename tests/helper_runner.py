import builtins
import importlib.machinery
import importlib.util
import json
import os
import sys

path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "omafile-helper")
spec = importlib.util.spec_from_loader("omafile_helper", importlib.machinery.SourceFileLoader("omafile_helper", path))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
options = json.loads(sys.argv[1])
real_open = builtins.open

def isolated_open(path, *args, **kwargs):
    if path == "/proc/mounts":
        path = options.get("mounts_file", os.devnull)
    return real_open(path, *args, **kwargs)

helper.open = isolated_open
if options.get("thumbnailers"):
    helper.THUMBNAILER_DIRS = (options["thumbnailers"],)
    helper.trusted_thumbnailer = lambda path: os.path.dirname(path) == options["thumbnailers"]
real_program = helper.trusted_program

def test_program(name):
    if name in options.get("programs", {}):
        return options["programs"][name]
    return real_program(name)

helper.trusted_program = test_program
helper.main()
