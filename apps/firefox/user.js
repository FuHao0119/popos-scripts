// ========================================================
// Firefox Linux 硬件视频编解码加速配置 (VA-API on Wayland)
// ========================================================

// 1. 开启系统 FFmpeg VA-API 硬件解码支持
user_pref("media.ffmpeg.vaapi.enabled", true);

// 2. 启用 RDD 媒体解码隔离进程中的 FFmpeg 硬件解码
user_pref("media.rdd-ffmpeg.enabled", true);

// 3. 强制开启完整的 WebRender 硬件渲染
user_pref("gfx.webrender.all", true);

// 4. 开启 Wayland 下的硬件直接纹理共享 (DMABUF 零拷贝视频输出)
user_pref("widget.dmabuf.force-enabled", true);

// 5. 开启通用硬件视频解码总开关
user_pref("media.hardware-video-decoding.enabled", true);

// 6. 禁用内置的纯 CPU 软件解码库 (ffvpx)，强制调用 Intel 核显硬件加速
user_pref("media.ffvpx.enabled", false);

// 7. 开启 AV1 格式视频的硬件解码支持 (12代 Intel Iris Xe 原生支持)
user_pref("media.av1.enabled", true);

// 8. 启用硬件视频处理与隔离
user_pref("media.rdd-process.enabled", true);
