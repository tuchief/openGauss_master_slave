#!/usr/bin/env python3
"""Binary-patch gaussdb to make MOT initialization a no-op on ARM64 Docker.

Primary patch: InitMOT() - the top-level entry point called by gaussdb startup.
Returns immediately, skipping all MOT initialization (NUMA, thread pools,
recovery manager, MOT adaptor, etc). This is safe because no MOT tables are
used in a standard openGauss deployment.

Secondary patches on known-problematic MOT functions serve as safety nets.

ARM64: mov w0,#0; ret  =  52800000 D65F03C0 (little-endian)
ARM64: ret (no-op)     =  D65F03C0
"""
import struct

# ARM64: mov w0, #0; ret
patch_ret0 = struct.pack('<II', 0x52800000, 0xD65F03C0)
# ARM64: ret (for void functions, just return immediately)
patch_ret = struct.pack('<I', 0xD65F03C0)

patches = [
    # === Primary: top-level MOT entry point (called by gaussdb startup) ===
    (0x1a52b20, patch_ret),   # InitMOT() - void, just return immediately

    # === Secondary: MOT engine init ===
    (0x1c0cd28, patch_ret0),  # MOT::MOTEngine::Initialize()

    # === Thread ID allocation (safety net) ===
    (0x1c36bf0, patch_ret0),  # MOT::AllocThreadId()
    (0x1c36dd0, patch_ret0),  # MOT::AllocThreadIdHighest()
    (0x1c36fc0, patch_ret0),  # MOT::AllocThreadIdNumaHighest(int)
    (0x1c371c8, patch_ret0),  # MOT::AllocThreadIdNumaCurrentHighest()

    # === NUMA node ID (safety net) ===
    (0x1c37760, patch_ret),   # MOT::InitCurrentNumaNodeId()
    (0x1c37b90, patch_ret),   # MOT::ClearCurrentNumaNodeId()
]

with open('/opt/software/openGauss/bin/gaussdb', 'r+b') as f:
    for off, data in patches:
        f.seek(off)
        f.write(data)
        ptype = "InitMOT(skip)" if off == 0x1a52b20 else \
                "engine init(ret0)" if off == 0x1c0cd28 else \
                "no-op" if len(data) == 4 else "ret0"
        print(f'Patched MOT at 0x{off:x} ({ptype})')
