"""
Image-build-time patch for crt-nodes/__init__.py.

Wraps the unguarded LTX23_Unified_Sampler + LTX23_Model_Loaders imports in a
try/except so the missing `ManualSigmas` symbol in newer ComfyUI versions
doesn't propagate and break the entire crt-nodes package registration.

Also appends a None-filter at the end of NODE_CLASS_MAPPINGS so any LTX23
entries that resolved to None get dropped before ComfyUI sees them.
"""
from pathlib import Path

p = Path('/comfyui/custom_nodes/crt-nodes/__init__.py')
body = p.read_text(encoding='utf-8')

if '[CRT-Nodes patched]' in body:
    print('crt-nodes already patched — skipping')
    raise SystemExit(0)

old_block = (
    "    from .py.LTX23_Unified_Sampler import (\n"
    "        CRT_LTX23USConfig,\n"
    "        CRT_LTX23USModelsPipe,\n"
    "        CRT_LTX23UnifiedSampler,\n"
    "    )\n"
    "    from .py.LTX23_Model_Loaders import (\n"
    "        CRT_LTX23AudioVAEAutoLoader,\n"
    "        CRT_LTX23BaseModelAutoLoader,\n"
    "        CRT_LTX23DualCLIPAutoLoader,\n"
    "        CRT_LTX23ICLoRAOutpaintAutoLoader,\n"
    "        CRT_LTX23ICLoRAUnionAutoLoader,\n"
    "        CRT_LTX23LatentUpscaleModelAutoLoader,\n"
    "        CRT_LTX23VideoVAEAutoLoader,\n"
    "    )\n"
)
new_block = (
    "    try:\n"
    "        from .py.LTX23_Unified_Sampler import (\n"
    "            CRT_LTX23USConfig,\n"
    "            CRT_LTX23USModelsPipe,\n"
    "            CRT_LTX23UnifiedSampler,\n"
    "        )\n"
    "        from .py.LTX23_Model_Loaders import (\n"
    "            CRT_LTX23AudioVAEAutoLoader,\n"
    "            CRT_LTX23BaseModelAutoLoader,\n"
    "            CRT_LTX23DualCLIPAutoLoader,\n"
    "            CRT_LTX23ICLoRAOutpaintAutoLoader,\n"
    "            CRT_LTX23ICLoRAUnionAutoLoader,\n"
    "            CRT_LTX23LatentUpscaleModelAutoLoader,\n"
    "            CRT_LTX23VideoVAEAutoLoader,\n"
    "        )\n"
    "    except Exception as _e:\n"
    "        print(f'[CRT-Nodes patched] LTX23 unavailable: {_e}')\n"
    "        CRT_LTX23USConfig = None\n"
    "        CRT_LTX23USModelsPipe = None\n"
    "        CRT_LTX23UnifiedSampler = None\n"
    "        CRT_LTX23AudioVAEAutoLoader = None\n"
    "        CRT_LTX23BaseModelAutoLoader = None\n"
    "        CRT_LTX23DualCLIPAutoLoader = None\n"
    "        CRT_LTX23ICLoRAOutpaintAutoLoader = None\n"
    "        CRT_LTX23ICLoRAUnionAutoLoader = None\n"
    "        CRT_LTX23LatentUpscaleModelAutoLoader = None\n"
    "        CRT_LTX23VideoVAEAutoLoader = None\n"
)

if old_block not in body:
    print('FAIL: crt-nodes LTX23 import block not found at expected location')
    raise SystemExit(1)

body = body.replace(old_block, new_block)
body += (
    "\n# [CRT-Nodes patched] filter None values\n"
    "try:\n"
    "    NODE_CLASS_MAPPINGS = {k: v for k, v in NODE_CLASS_MAPPINGS.items() if v is not None}\n"
    "    if 'NODE_DISPLAY_NAME_MAPPINGS' in dir():\n"
    "        NODE_DISPLAY_NAME_MAPPINGS = {k: v for k, v in NODE_DISPLAY_NAME_MAPPINGS.items() if k in NODE_CLASS_MAPPINGS}\n"
    "except Exception as _e_filter:\n"
    "    print(f'[CRT-Nodes patched] filter step failed: {_e_filter}')\n"
)

p.write_text(body, encoding='utf-8')
print(f'crt-nodes patched: {len(body)} bytes written')
