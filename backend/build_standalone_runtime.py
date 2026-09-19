"""
أداة بناء وتجهيز بيئة بايثون المحمولة المستقلة (Standalone Python Runtime Packager)
تنشئ مجلد python_runtime يحتوي على كافة المكتبات والمحركات لتضمينه مع مثبت Inno Setup
"""

import os
import sys
import shutil
import subprocess

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
RUNTIME_DIR = os.path.join(BASE_DIR, "python_runtime")
PY_SRC = sys.prefix

print(f"[*] Starting Standalone Runtime Packaging...")
print(f"[*] Source Python: {PY_SRC}")
print(f"[*] Target Directory: {RUNTIME_DIR}")

os.makedirs(RUNTIME_DIR, exist_ok=True)

# 1. Copy base executables & core DLLs
core_files = [
    "python.exe", "pythonw.exe", "python3.dll", "python312.dll",
    "vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll", "msvcp140_1.dll", "msvcp140_2.dll"
]

for fname in os.listdir(PY_SRC):
    fpath = os.path.join(PY_SRC, fname)
    if os.path.isfile(fpath):
        if fname.lower().endswith(('.exe', '.dll', '.ico')) or fname.lower() in core_files:
            dest = os.path.join(RUNTIME_DIR, fname)
            print(f" -> Copying root file: {fname}")
            shutil.copy2(fpath, dest)

# 2. Copy DLLs folder if exists
src_dlls = os.path.join(PY_SRC, "DLLs")
dest_dlls = os.path.join(RUNTIME_DIR, "DLLs")
if os.path.exists(src_dlls):
    print(f"[*] Copying Python DLLs...")
    shutil.copytree(src_dlls, dest_dlls, dirs_exist_ok=True)

# 3. Copy Lib folder (excluding test and unnecessary dev files)
src_lib = os.path.join(PY_SRC, "Lib")
dest_lib = os.path.join(RUNTIME_DIR, "Lib")
print(f"[*] Copying Standard Library and site-packages (this may take a minute)...")

def ignore_patterns(path, names):
    ignored = set()
    for name in names:
        if name in ("__pycache__", "test", "tests", "idle_test"):
            ignored.add(name)
        elif name.endswith((".pyc", ".pyo")):
            ignored.add(name)
    return ignored

shutil.copytree(src_lib, dest_lib, ignore=ignore_patterns, dirs_exist_ok=True)

# 4. Create pyvenv.cfg for isolated standalone execution
pyvenv_cfg = os.path.join(RUNTIME_DIR, "pyvenv.cfg")
with open(pyvenv_cfg, "w", encoding="utf-8") as f:
    f.write(f"home = .\ninclude-system-site-packages = false\nversion = 3.12.10\nexecutable = .\\python.exe\ncommand = .\\python.exe\n")

print(f"[+] Python standalone runtime created successfully at: {RUNTIME_DIR}")

# 5. Verification Test
test_py = os.path.join(RUNTIME_DIR, "python.exe")
print(f"[*] Testing standalone python runtime: {test_py}")

test_code = """
import sys
print(f"[OK] Standalone Python version: {sys.version.split()[0]}")
import fastapi
import uvicorn
import onnxruntime as ort
import sherpa_onnx
import soundfile
import librosa
import torch
import transformers
print(f"[OK] All core packages imported successfully!")
print(f"[OK] ONNX Providers: {ort.get_available_providers()}")
"""

res = subprocess.run([test_py, "-c", test_code], capture_output=True, text=True)
print(res.stdout)
if res.stderr:
    print("Stderr:", res.stderr)

if res.returncode == 0:
    print("[SUCCESS] Standalone Python Runtime is 100% READY for Inno Setup packaging!")
else:
    print("[FAILED] Standalone Python Runtime test returned errors.")
