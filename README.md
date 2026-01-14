# TrueHD and VF Filter (Unmanic plugin)

Queues files during **Library Management -> File test** when:
- File contains **TrueHD/MLP**
- **VF/FR** (and/or original language) does **not** already have an **AC3/EAC3** fallback
- A **TrueHD/MLP** source exists for the language(s) that need conversion

## Install (local)
Copy this folder to:
/config/.unmanic/plugins/jf_truehd_vf_filetest

Restart Unmanic, then add the plugin in:
Library -> Plugin Flow -> Library Management - File test
