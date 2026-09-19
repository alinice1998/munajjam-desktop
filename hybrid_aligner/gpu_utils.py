"""
أدوات كشف وإدارة بطاقات المعالجة الرسومية (GPU Detection & DirectML/CUDA Provider Helpers)
"""

import os
import sys
import subprocess
from typing import List, Any, Optional

_CACHED_DML_DEVICE_ID: Optional[int] = None

def get_best_dml_device_id() -> int:
    """
    يكتشف تلقائياً معرّف بطاقة الشاشة المنفصلة عالية الأداء (NVIDIA / AMD) لمسرع DirectML.
    في أجهزة الحواسيب المحمولة بنظام Windows (Hybrid GPUs):
    - عادة ما يكون device_id 0 هو كرت الشاشة المدمج (Intel/AMD iGPU).
    - ويكون device_id 1 هو كرت الشاشة المنفصل عالي الأداء (NVIDIA GeForce RTX).
    """
    global _CACHED_DML_DEVICE_ID
    if _CACHED_DML_DEVICE_ID is not None:
        return _CACHED_DML_DEVICE_ID

    # 1. التحقق أولاً من المتغيرات البيئية إذا تم تحديدها يدوياً
    for env_var in ["DML_DEVICE_ID", "GPU_DEVICE_ID", "DIRECTML_DEVICE_ID"]:
        if env_var in os.environ:
            try:
                _CACHED_DML_DEVICE_ID = int(os.environ[env_var])
                print(f"[+] Using specified DirectML GPU Device ID from {env_var}: {_CACHED_DML_DEVICE_ID}")
                return _CACHED_DML_DEVICE_ID
            except ValueError:
                pass

    try:
        # التحقق من وجود كرت NVIDIA عبر nvidia-smi بدون إظهار أي نافذة كونسول
        has_nvidia = False
        try:
            kwargs = {}
            if sys.platform == "win32":
                kwargs["creationflags"] = subprocess.CREATE_NO_WINDOW
            out = subprocess.check_output(["nvidia-smi"], stderr=subprocess.DEVNULL, **kwargs).decode()
            if "NVIDIA" in out:
                has_nvidia = True
        except Exception:
            pass

        if has_nvidia:
            _CACHED_DML_DEVICE_ID = 1
            return _CACHED_DML_DEVICE_ID
    except Exception:
        pass

    _CACHED_DML_DEVICE_ID = 0
    return _CACHED_DML_DEVICE_ID

def get_ort_execution_providers() -> List[Any]:
    """
    إرجاع قائمة مزودي التشغيل (Execution Providers) مرتبة حسب الأفضلية والأداء:
    1. CUDAExecutionProvider (إذا كان متاحاً)
    2. DmlExecutionProvider (مع توجيهه للكرت المنفصل عالي الأداء)
    3. CPUExecutionProvider
    """
    import onnxruntime as ort
    available = ort.get_available_providers()
    providers = []

    # تحديد معرّف الكرت لـ CUDA
    cuda_device_id = 0
    for env_var in ["CUDA_DEVICE_ID", "GPU_DEVICE_ID"]:
        if env_var in os.environ and "CUDA_VISIBLE_DEVICES" not in os.environ:
            try:
                cuda_device_id = int(os.environ[env_var])
            except ValueError:
                pass

    if "CUDAExecutionProvider" in available:
        providers.append(("CUDAExecutionProvider", {"device_id": cuda_device_id}))

    if "DmlExecutionProvider" in available:
        best_device_id = get_best_dml_device_id()
        providers.append(("DmlExecutionProvider", {"device_id": best_device_id}))

    providers.append("CPUExecutionProvider")
    return providers
