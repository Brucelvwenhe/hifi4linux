#!/usr/bin/env python3
# ============================================================
#  musicd —— 本地音乐播放器后端
#
#  · 曲库扫描（ffprobe 读标签 + 真实采样率/位深）
#  · 音频引擎 mpv（JSON IPC 控制，可切 ALSA 独占做 bit-perfect）
#  · 歌词（.lrc 外挂 / 内嵌标签）
#  · 专辑封面（ffmpeg 提取）
#  · HTTP API 走 127.0.0.1，供 QML 前端调用
#
#  只依赖：python3 标准库 + ffprobe/ffmpeg + mpv + hifi-mode
# ============================================================
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HOME = os.path.expanduser("~")
MUSIC_DIRS = [d for d in os.environ.get(
    "HIFI_MUSIC_DIRS", os.path.join(HOME, "音乐")).split(":") if d]
CACHE_DIR = os.path.join(HOME, ".cache", "musicd")
LIB_CACHE = os.path.join(CACHE_DIR, "library.json")
ART_CACHE = os.path.join(CACHE_DIR, "art")
MPV_SOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "musicd-mpv.sock")
HIFI_BIN = os.environ.get("HIFI_BIN", os.path.join(HOME, ".local", "bin", "hifi-mode"))
PORT = int(os.environ.get("MUSICD_PORT", "8787"))
AUDIO_EXT = (".flac", ".wav", ".ape", ".dsf", ".dff", ".m4a", ".mp3",
             ".ogg", ".opus", ".wv", ".aiff", ".aif", ".wma")

os.makedirs(CACHE_DIR, exist_ok=True)
os.makedirs(ART_CACHE, exist_ok=True)

# ---------------------------------------------------------------
#  mpv 控制
# ---------------------------------------------------------------
class Mpv:
    def __init__(self):
        self.proc = None
        self.sock = None
        self.rid = 0
        self.lock = threading.Lock()
        self.hifi = False
        self._start()

    def _dac_card(self):
        """找 USB DAC 的 ALSA 卡号（有 usbid 的即为 USB 声卡）"""
        for i in range(32):
            if os.path.exists(f"/proc/asound/card{i}/usbid"):
                return i
        return None

    def _kill_stale(self):
        """清掉其它还在用同一个 IPC socket 的 mpv。
        后端重启后旧 mpv 会变成孤儿进程，却仍以 ALSA 独占方式占着
        声卡 —— 新 mpv 打不开设备就完全放不出声。"""
        try:
            out = subprocess.run(
                ["pgrep", "-f", f"input-ipc-server={MPV_SOCK}"],
                capture_output=True, text=True).stdout.split()
            me = str(self.proc.pid) if self.proc else ""
            for pid in out:
                if pid and pid != me:
                    subprocess.run(["kill", "-9", pid], capture_output=True)
            if out:
                time.sleep(0.3)
        except Exception:
            pass

    def _start(self):
        if self.proc and self.proc.poll() is None:
            return
        if os.path.exists(MPV_SOCK):
            try: os.unlink(MPV_SOCK)
            except OSError: pass
        args = ["mpv", "--idle=yes", "--no-video", "--no-terminal",
                f"--input-ipc-server={MPV_SOCK}",
                "--volume=100",
                "--audio-display=no", "--really-quiet"]
        if self.hifi:
            card = self._dac_card()
            if card is not None:
                args += ["--ao=alsa", f"--audio-device=alsa/hw:{card},0",
                         "--audio-exclusive=yes"]
            else:
                args += ["--ao=pipewire"]
        else:
            args += ["--ao=pipewire"]
        self._kill_stale()
        self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL)
        for _ in range(50):
            if os.path.exists(MPV_SOCK):
                try:
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.connect(MPV_SOCK)
                    s.settimeout(2.0)
                    self.sock = s
                    return
                except OSError:
                    pass
            time.sleep(0.1)

    def cmd(self, *args):
        with self.lock:
            self._start()
            if not self.sock:
                return None
            self.rid += 1
            rid = self.rid
            msg = json.dumps({"command": list(args), "request_id": rid}) + "\n"
            try:
                self.sock.sendall(msg.encode())
                buf = b""
                deadline = time.time() + 2.0
                while time.time() < deadline:
                    chunk = self.sock.recv(65536)
                    if not chunk:
                        raise OSError("mpv 断开")
                    buf += chunk
                    for line in buf.split(b"\n"):
                        if not line.strip():
                            continue
                        try:
                            obj = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        if obj.get("request_id") == rid:
                            return obj.get("data")
            except OSError:
                self.sock = None
                self.proc = None
            return None

    def get(self, prop):
        return self.cmd("get_property", prop)

    _pending_path = None

    def stop_and_release(self):
        """彻底停止 mpv 并释放 ALSA 设备（切模式前必须做）"""
        try:
            self.cmd("stop")
        except Exception:
            pass
        try:
            self.cmd("quit")
        except Exception:
            pass
        if self.proc:
            try:
                self.proc.terminate()
                self.proc.wait(timeout=2)
            except Exception:
                try: self.proc.kill()
                except Exception: pass
        if self.sock:
            try: self.sock.close()
            except Exception: pass
        self.proc = None
        self.sock = None
        time.sleep(0.4)

    def load(self, path):
        """载入曲目。ALSA 独占模式下必须重开设备：
        mpv 会保持音频设备打开，换到不同采样率的曲目时不会重新协商，
        硬件就停在旧采样率上，新曲目被静默重采样。"""
        self._pending_path = path
        if self.hifi:
            try:
                self.cmd("quit")
            except Exception:
                pass
            if self.proc:
                try: self.proc.terminate()
                except Exception: pass
            if self.sock:
                try: self.sock.close()
                except Exception: pass
            self.proc = None
            self.sock = None
            time.sleep(0.35)
            self._start()
        return self.cmd("loadfile", path, "replace")

    def restart(self, hifi):
        """切换 bit-perfect 模式需要重启 mpv（音频后端要换）"""
        cur = None
        try:
            cur = self.get("path")
        except Exception:
            pass
        pos = self.get("time-pos") or 0
        paused = self.get("pause")
        self.hifi = hifi
        try:
            self.cmd("quit")
        except Exception:
            pass
        if self.proc:
            try: self.proc.terminate()
            except Exception: pass
        if self.sock:
            try: self.sock.close()
            except Exception: pass
        self.proc = None
        self.sock = None
        time.sleep(0.4)
        self._start()
        if cur:
            self.cmd("loadfile", cur, "replace")
            time.sleep(0.4)
            if pos:
                self.cmd("seek", pos, "absolute")
            if paused:
                self.cmd("set_property", "pause", True)


MPV = Mpv()

# ---------------------------------------------------------------
#  曲库
# ---------------------------------------------------------------
LIB = {"tracks": [], "scanned": 0}
LIB_LOCK = threading.Lock()


def probe(path):
    """用 ffprobe 读标签与真实格式"""
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "quiet", "-print_format", "json",
             "-show_format", "-show_streams", path],
            capture_output=True, text=True, timeout=15).stdout
        j = json.loads(out or "{}")
    except Exception:
        return None
    fmt = j.get("format", {})
    tags = {k.lower(): v for k, v in (fmt.get("tags") or {}).items()}
    astream = next((s for s in j.get("streams", [])
                    if s.get("codec_type") == "audio"), {})
    if not astream:
        return None
    bits = astream.get("bits_per_raw_sample") or astream.get("bits_per_sample") or ""
    try:
        bits = int(bits)
        if bits == 0:
            bits = ""
    except (TypeError, ValueError):
        bits = ""
    return {
        "path": path,
        "title": tags.get("title") or os.path.splitext(os.path.basename(path))[0],
        "artist": tags.get("artist") or tags.get("album_artist") or "未知艺术家",
        "album": tags.get("album") or os.path.basename(os.path.dirname(path)),
        "track": tags.get("track") or "",
        "lyrics_tag": tags.get("lyrics") or tags.get("unsyncedlyrics") or "",
        "codec": (astream.get("codec_name") or "").upper(),
        "rate": int(astream.get("sample_rate") or 0),
        "bits": bits,
        "channels": astream.get("channels") or 0,
        "lossless": (astream.get("codec_name") or "") in
                    ("flac", "alac", "wav", "ape", "dsd_lsbf", "dsd_msbf", "tak", "wavpack", "tta"),
        "duration": float(fmt.get("duration") or 0),
        "size": int(fmt.get("size") or 0),
    }


def scan_library():
    global LIB
    tracks, seen = [], set()
    for root_dir in MUSIC_DIRS:
        if not os.path.isdir(root_dir):
            continue
        for base, _dirs, files in os.walk(root_dir):
            for fn in sorted(files):
                if not fn.lower().endswith(AUDIO_EXT):
                    continue
                p = os.path.join(base, fn)
                if p in seen:
                    continue
                seen.add(p)
                t = probe(p)
                if t:
                    tracks.append(t)
    tracks.sort(key=lambda t: (t["artist"], t["album"], str(t.get("track") or ""), t["title"]))
    with LIB_LOCK:
        LIB = {"tracks": tracks, "scanned": int(time.time())}
    try:
        with open(LIB_CACHE, "w", encoding="utf-8") as f:
            json.dump(LIB, f, ensure_ascii=False)
    except OSError:
        pass
    return len(tracks)


def load_library():
    global LIB
    if os.path.exists(LIB_CACHE):
        try:
            with open(LIB_CACHE, encoding="utf-8") as f:
                LIB = json.load(f)
            return
        except Exception:
            pass
    scan_library()


# ---------------------------------------------------------------
#  歌词
# ---------------------------------------------------------------
LRC_RE = re.compile(r"\[(\d+):(\d+(?:[.:]\d+)?)\]")


def parse_lrc(text):
    lines = []
    for raw in text.splitlines():
        stamps = LRC_RE.findall(raw)
        content = LRC_RE.sub("", raw).strip()
        if not content:
            continue
        for mm, ss in stamps:
            try:
                t = int(mm) * 60 + float(ss.replace(":", "."))
            except ValueError:
                continue
            lines.append({"t": round(t, 2), "text": content})
    lines.sort(key=lambda x: x["t"])
    return lines


def get_lyrics(idx):
    with LIB_LOCK:
        tracks = LIB["tracks"]
    if idx < 0 or idx >= len(tracks):
        return {"lines": [], "source": "none"}
    t = tracks[idx]
    lrc = os.path.splitext(t["path"])[0] + ".lrc"
    if os.path.exists(lrc):
        try:
            with open(lrc, encoding="utf-8", errors="ignore") as f:
                lines = parse_lrc(f.read())
            if lines:
                return {"lines": lines, "source": "lrc"}
        except OSError:
            pass
    if t.get("lyrics_tag"):
        return {"lines": parse_lrc(t["lyrics_tag"]), "source": "tag"}
    return {"lines": [], "source": "none"}


# ---------------------------------------------------------------
#  封面
# ---------------------------------------------------------------
def get_art(idx):
    with LIB_LOCK:
        tracks = LIB["tracks"]
    if idx < 0 or idx >= len(tracks):
        return None
    path = tracks[idx]["path"]
    key = f"{abs(hash(path)):x}.jpg"
    out = os.path.join(ART_CACHE, key)
    if os.path.exists(out) and os.path.getsize(out) > 0:
        return out
    # 优先同目录 cover/folder 图
    d = os.path.dirname(path)
    for name in ("cover.jpg", "Cover.jpg", "folder.jpg", "Folder.jpg",
                 "cover.png", "front.jpg", "album.jpg"):
        cand = os.path.join(d, name)
        if os.path.exists(cand):
            return cand
    # 从音频文件里抽内嵌图
    try:
        r = subprocess.run(
            ["ffmpeg", "-v", "quiet", "-y", "-i", path, "-an",
             "-vcodec", "mjpeg", "-frames:v", "1", "-f", "image2", out],
            capture_output=True, timeout=20)
        if os.path.exists(out) and os.path.getsize(out) > 0:
            return out
    except Exception:
        pass
    return None


HIFI_CACHE = {"raw": "off|||||||||||", "ts": 0.0}


def _hifi_raw():
    """调用 hifi-mode status。
    必须带 HIFI_NO_PLAYER=1：否则会形成
    后端 /state -> hifi-mode status -> curl /state -> … 的无限递归，
    导致接口卡 5 秒（UI 跟着卡死）"""
    env = dict(os.environ)
    env["HIFI_NO_PLAYER"] = "1"
    return subprocess.run([HIFI_BIN, "status"], capture_output=True,
                          text=True, timeout=6, env=env).stdout.strip()


def hifi_state():
    """读 hifi-mode 的当前开关状态"""
    try:
        p = _hifi_raw().split("|")
        return (p[0] == "on") if p else False
    except Exception:
        return False


def hifi_sync_loop():
    """常驻线程：HiFi 模式一变，立刻按新模式重建 mpv（更换音频后端）。
    这一步是关键 —— 桌面组件切 HiFi 时播放器必须跟着切到 ALSA 独占，
    否则音频仍然走 PipeWire 被重采样，等于开关白开。"""
    while True:
        try:
            raw = _hifi_raw()
            HIFI_CACHE["raw"] = raw
            HIFI_CACHE["ts"] = time.time()
            p = raw.split("|")
            want = (p[0] == "on") if p else False
            if want != MPV.hifi:
                print(f"musicd: HiFi 模式 -> {want}，切换音频后端", flush=True)
                # 顺序很重要：
                #  1) 先让 mpv 彻底放开 ALSA 设备（独占时不放开，
                #     PipeWire 抢不回设备，浏览器和播放器会同时没声音）
                #  2) 再切模式
                #  3) 关掉直出时，强制 PipeWire 重新打开 DAC
                MPV.stop_and_release()
                MPV.hifi = want
                MPV._start()
                if not want:
                    _bounce_pipewire_sink()
                path = MPV._pending_path
                if path:
                    time.sleep(1.2)          # 等 mpv 真正就绪
                    for _try in range(3):
                        r = MPV.cmd("loadfile", path, "replace")
                        if r is not None:
                            break
                        time.sleep(1.0)
        except Exception as e:
            print(f"musicd: 模式切换出错 {e}", flush=True)
        time.sleep(2)


def _usb_sinks():
    try:
        out = subprocess.run(["pactl", "-f", "json", "list", "sinks"],
                             capture_output=True, text=True, timeout=6).stdout
        return [x["name"] for x in json.loads(out)
                if (x.get("properties", {}).get("device.bus") or "") == "usb"]
    except Exception:
        return []


def _bounce_pipewire_sink():
    """让 PipeWire 重新接管 USB DAC。

    独占模式期间 ALSA 设备被 mpv 占着，wireplumber 探测失败时
    会静默地不给这个设备创建 sink —— 结果 DAC 从 PipeWire 里
    整个消失，关掉直出后浏览器/播放器全都发不出声（用户遇到的
    "两个都没声音"）。这种情况 suspend 是救不回来的，
    必须重启 wireplumber 让它重新枚举设备。"""
    usb = _usb_sinks()
    if not usb:
        # DAC 已从 PipeWire 消失 —— 重启 wireplumber 重新发现
        print("musicd: PipeWire 中找不到 USB DAC，重启 wireplumber 恢复",
              flush=True)
        try:
            subprocess.run(["systemctl", "--user", "restart", "wireplumber"],
                           capture_output=True, timeout=20)
        except Exception:
            pass
        for _ in range(20):
            time.sleep(0.7)
            usb = _usb_sinks()
            if usb:
                break
        print(f"musicd: 恢复后找到 {len(usb)} 个 USB sink", flush=True)
    for name in usb:
        subprocess.run(["pactl", "suspend-sink", name, "1"],
                       capture_output=True, timeout=5)
    time.sleep(0.4)
    for name in usb:
        subprocess.run(["pactl", "suspend-sink", name, "0"],
                       capture_output=True, timeout=5)
    # 把默认输出指回 DAC（重启 wireplumber 后默认设备会跳到内建声卡）
    if usb:
        subprocess.run(["pactl", "set-default-sink", usb[0]],
                       capture_output=True, timeout=5)


# ---------------------------------------------------------------
#  频谱可视化
#  用 ffmpeg 的 showspectrum 直接从文件解码算频谱 —— 这样无论是
#  PipeWire 共享输出还是 ALSA 独占直出，都能正常显示（监听系统音频
#  的方案在独占模式下会是一片死寂）
# ---------------------------------------------------------------
SPEC_BANDS = 64
SPEC_W = 4                     # 每帧时间列数（取最后一列）
SPEC_HDR = len(f"P6\n{SPEC_W} {SPEC_BANDS}\n255\n")
SPEC_FRAME = SPEC_HDR + SPEC_W * SPEC_BANDS * 3
_spec = {"vals": [0.0] * SPEC_BANDS}
_spec_lock = threading.Lock()
_spec_proc = [None]


def _column_intensities(buf, width, height, col=-1):
    """从 showspectrum 输出的 PPM 里取一列 —— 注意 showspectrum 的
    X 轴是时间、Y 轴才是频率，所以一列 = 一个时刻的频谱"""
    i = buf.find(b"255\n")
    if i < 0:
        return None
    px = buf[i + 4:i + 4 + width * height * 3]
    if len(px) < width * height * 3:
        return None
    c = width - 1 if col < 0 else col
    return [max(px[(r * width + c) * 3],
                px[(r * width + c) * 3 + 1],
                px[(r * width + c) * 3 + 2]) / 255.0
            for r in range(height)]


def spectrum_loop():
    """常驻线程：跟随当前曲目与进度，持续更新频谱"""
    cur_path, cur_pos, proc, buf = None, -1.0, None, b""
    while True:
        try:
            path = MPV.get("path")
            paused = MPV.get("pause")
            pos = MPV.get("time-pos") or 0
        except Exception:
            time.sleep(0.5)
            continue

        need_new = (
            proc is None or proc.poll() is not None
            or path != cur_path
            or abs(pos - cur_pos) > 2.5
        )
        if path and not paused and need_new:
            if proc and proc.poll() is None:
                try: proc.kill()
                except Exception: pass
            cur_path, cur_pos, buf = path, pos, b""
            try:
                proc = subprocess.Popen(
                    ["ffmpeg", "-v", "quiet", "-ss", f"{max(0, pos):.2f}",
                     "-i", path,
                     "-lavfi", f"showspectrum=s={SPEC_W}x{SPEC_BANDS}"
                               f":mode=combined:color=intensity:scale=log:fps=25",
                     "-f", "image2pipe", "-vcodec", "ppm", "-"],
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                _spec_proc[0] = proc
            except Exception:
                proc = None
                time.sleep(1)
                continue

        if proc and proc.poll() is None:
            try:
                chunk = proc.stdout.read(SPEC_FRAME * 2)
            except Exception:
                chunk = b""
            if chunk:
                buf += chunk
                vals = None
                while len(buf) >= SPEC_FRAME:
                    j = buf.find(b"P6")
                    if j < 0:
                        buf = b""
                        break
                    buf = buf[j:]
                    if len(buf) < SPEC_FRAME:
                        break
                    v = _column_intensities(buf[:SPEC_FRAME], SPEC_W, SPEC_BANDS)
                    buf = buf[SPEC_FRAME:]
                    if v:
                        vals = v
                if vals:
                    with _spec_lock:
                        # 低频在左：把行序翻过来（row 0 = 最低频）
                        _spec["vals"] = list(reversed(vals))
        elif not path or paused:
            with _spec_lock:
                _spec["vals"] = [0.0] * SPEC_BANDS
            time.sleep(0.3)
        else:
            time.sleep(0.1)


# ---------------------------------------------------------------
#  音质检测（真无损 or 有损转码）
#  原理与 Spek / foobar 的"频谱看砖墙"一样：有损编码会把某频率以上
#  的信息全部丢掉，频谱上出现明显的高频截止
# ---------------------------------------------------------------
QUALITY_CACHE = os.path.join(CACHE_DIR, "quality.json")
_quality = {}
_quality_lock = threading.Lock()


def _load_quality():
    try:
        with open(QUALITY_CACHE, encoding="utf-8") as f:
            _quality.update(json.load(f))
    except Exception:
        pass


def _save_quality():
    try:
        with open(QUALITY_CACHE, "w", encoding="utf-8") as f:
            json.dump(_quality, f, ensure_ascii=False)
    except OSError:
        pass


_load_quality()


def analyze_quality(idx, seconds=40):
    with LIB_LOCK:
        tracks = LIB["tracks"]
    if idx < 0 or idx >= len(tracks):
        return {"ok": False}
    t = tracks[idx]
    path = t["path"]
    key = f"{path}:{os.path.getmtime(path):.0f}"
    with _quality_lock:
        if key in _quality:
            return _quality[key]

    BANDS = 1024
    W = 2
    hdr = len(f"P6\n{W} {BANDS}\n255\n")
    frame_size = hdr + W * BANDS * 3
    try:
        p = subprocess.run(
            ["ffmpeg", "-v", "quiet", "-t", str(seconds), "-i", path,
             "-lavfi", f"showspectrum=s={W}x{BANDS}:mode=combined"
                       f":color=intensity:scale=log:fps=4",
             "-f", "image2pipe", "-vcodec", "ppm", "-"],
            capture_output=True, timeout=240)
        data = p.stdout
    except Exception as e:
        return {"ok": False, "error": str(e)}

    avg = [0.0] * BANDS
    n = 0
    while True:
        j = data.find(b"P6")
        if j < 0 or len(data) - j < frame_size:
            break
        col = _column_intensities(data[j:j + frame_size], W, BANDS)
        if not col:
            data = data[j + frame_size:]
            continue
        for k in range(BANDS):
            avg[k] += col[k]
        n += 1
        data = data[j + frame_size:]

    if n == 0:
        return {"ok": False, "error": "无频谱数据"}

    avg = [v / n for v in avg]
    peak = max(avg) or 1.0
    # 行 0 = 最低频（见 spectrum_loop 的说明），从高端往下找第一个有能量的频点
    floor = peak * 0.05
    cutoff_bin = 0
    for k in range(BANDS - 1, -1, -1):
        if avg[k] >= floor:
            cutoff_bin = k
            break
    nyq = (t["rate"] or 44100) / 2.0
    cutoff = cutoff_bin / (BANDS - 1) * nyq if BANDS > 1 else nyq

    # 判定
    ratio = cutoff / nyq if nyq else 0
    if ratio >= 0.95:
        verdict, level = "真无损（频响完整）", "good"
    elif ratio >= 0.88:
        verdict, level = f"疑似高码率有损转码（截止 {cutoff/1000:.1f} kHz）", "warn"
    elif ratio >= 0.70:
        verdict, level = f"疑似有损转码（截止 {cutoff/1000:.1f} kHz）", "warn"
    else:
        verdict, level = f"明显有损/升频（截止 {cutoff/1000:.1f} kHz）", "bad"

    res = {"ok": True, "idx": idx, "bands": BANDS, "cutoff": round(cutoff / 1000, 1),
           "nyquist": round(nyq / 1000, 1), "ratio": round(ratio, 3),
           "verdict": verdict, "level": level,
           "codec": t["codec"], "rate": t["rate"], "bits": t["bits"],
           "frames": n,
           "spectrum": [round(v / peak, 3) for v in avg[::max(1, BANDS // 128)]]}
    with _quality_lock:
        _quality[key] = res
        _save_quality()
    return res


# ---------------------------------------------------------------
#  HTTP API
# ---------------------------------------------------------------
ALL_TRACKS = []          # 前端可见的播放队列

# ---------------------------------------------------------------
#  外观配置（前端可调，存盘持久化）
# ---------------------------------------------------------------
CFG_PATH = os.path.join(os.path.expanduser("~"), ".config", "musicplayer.json")
CFG = {"opacity": 0.85}


def load_cfg():
    try:
        with open(CFG_PATH, encoding="utf-8") as f:
            CFG.update(json.load(f))
    except Exception:
        pass


def save_cfg():
    try:
        os.makedirs(os.path.dirname(CFG_PATH), exist_ok=True)
        with open(CFG_PATH, "w", encoding="utf-8") as f:
            json.dump(CFG, f, ensure_ascii=False, indent=2)
    except OSError:
        pass


load_cfg()


def state():
    with LIB_LOCK:
        tracks = LIB["tracks"]
    path = MPV.get("path")
    pos = MPV.get("time-pos") or 0
    dur = MPV.get("duration") or 0
    paused = MPV.get("pause")
    vol = MPV.get("volume") or 100
    idx = -1
    if path:
        for i, t in enumerate(tracks):
            if t["path"] == path:
                idx = i
                break
    t = tracks[idx] if 0 <= idx < len(tracks) else None
    # 用后台线程维护的缓存（直接起子进程会让接口慢 5 秒）
    if time.time() - HIFI_CACHE["ts"] > 6:
        try:
            HIFI_CACHE["raw"] = _hifi_raw()
            HIFI_CACHE["ts"] = time.time()
        except Exception:
            pass
    hp = HIFI_CACHE["raw"].split("|")
    # 直出判定由后端自己算：独占模式下 PipeWire 看不到流，
    # hifi-mode 那边拿不到源采样率，只有我们知道当前曲目的真实采样率
    _link = 0
    if len(hp) > 2 and str(hp[2]).isdigit():
        _link = int(hp[2])
    # 只有"播放器真的在放"且链路采样率与源一致，才算直出。
    # 否则浏览器放视频时（我们的 mpv 只是挂着文件/暂停）会误报直出。
    _actually_playing = bool(path) and not bool(paused)
    _bp = bool(_actually_playing and t and _link and t.get("rate") == _link)
    return {
        "ok": True,
        "idx": idx,
        "playing": bool(path),
        "paused": bool(paused),
        "pos": round(pos or 0, 2),
        "dur": round(dur or 0, 2),
        "vol": round(vol or 100),
        "title": t["title"] if t else "",
        "artist": t["artist"] if t else "",
        "album": t["album"] if t else "",
        "codec": t["codec"] if t else "",
        "rate": t["rate"] if t else 0,
        "bits": t["bits"] if t else "",
        "lossless": t["lossless"] if t else False,
        "hifi": (hp[0] == "on") if hp else False,
        "hifi_src_rate": hp[1] if len(hp) > 1 else "",
        "hifi_link_rate": hp[2] if len(hp) > 2 else "",
        "hifi_bitperfect": _bp,
        "hifi_dac": hp[8] if len(hp) > 8 else "",
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        p = u.path
        with LIB_LOCK:
            tracks = LIB["tracks"]
        try:
            if p == "/state":
                return self._send(200, state())

            if p == "/library":
                albums = {}
                for i, t in enumerate(tracks):
                    k = (t["album"], t["artist"])
                    albums.setdefault(k, []).append(i)
                out = [{"album": k[0], "artist": k[1], "tracks": v}
                       for k, v in sorted(albums.items(), key=lambda x: (x[0][1], x[0][0]))]
                return self._send(200, {"count": len(tracks), "albums": out,
                                        "tracks": [{"i": i, "title": t["title"],
                                                    "artist": t["artist"], "album": t["album"],
                                                    "rate": t["rate"], "bits": t["bits"],
                                                    "codec": t["codec"], "dur": round(t["duration"], 1)}
                                                   for i, t in enumerate(tracks)]})

            if p == "/search":
                kw = (q.get("q", [""])[0] or "").lower()
                if not kw:
                    return self._send(200, {"tracks": []})
                res = [{"i": i, "title": t["title"], "artist": t["artist"], "album": t["album"]}
                       for i, t in enumerate(tracks)
                       if kw in t["title"].lower() or kw in t["artist"].lower()
                       or kw in t["album"].lower()]
                return self._send(200, {"tracks": res[:200], "total": len(res)})

            if p == "/play":
                i = int(q.get("i", ["-1"])[0])
                if 0 <= i < len(tracks):
                    MPV.load(tracks[i]["path"])
                    return self._send(200, {"ok": True, "i": i})
                return self._send(200, {"ok": False})

            if p == "/toggle":
                cur = MPV.get("pause")
                MPV.cmd("set_property", "pause", not bool(cur))
                return self._send(200, {"ok": True})
            if p == "/next":
                MPV.cmd("playlist-next", "force")
                return self._send(200, {"ok": True})
            if p == "/prev":
                MPV.cmd("playlist-prev", "force")
                return self._send(200, {"ok": True})
            if p == "/stop":
                MPV.cmd("stop")
                return self._send(200, {"ok": True})
            if p == "/seek":
                MPV.cmd("seek", float(q.get("t", ["0"])[0]), "absolute")
                return self._send(200, {"ok": True})
            if p == "/volume":
                MPV.cmd("set_property", "volume", float(q.get("v", ["100"])[0]))
                return self._send(200, {"ok": True})

            if p == "/lyrics":
                return self._send(200, get_lyrics(int(q.get("i", ["-1"])[0])))

            if p == "/art":
                f = get_art(int(q.get("i", ["-1"])[0]))
                if f:
                    with open(f, "rb") as fh:
                        data = fh.read()
                    return self._send(200, data, "image/jpeg")
                return self._send(404, b"", "image/jpeg")

            if p == "/spectrum":
                with _spec_lock:
                    return self._send(200, {"vals": _spec["vals"], "bands": SPEC_BANDS})

            if p == "/quality":
                i = int(q.get("i", [str(state()["idx"])])[0])
                if q.get("cached", ["0"])[0] == "1":
                    with LIB_LOCK:
                        tr = LIB["tracks"]
                    if 0 <= i < len(tr):
                        k = f"{tr[i]['path']}:{os.path.getmtime(tr[i]['path']):.0f}"
                        with _quality_lock:
                            if k in _quality:
                                return self._send(200, _quality[k])
                    return self._send(200, {"ok": False, "cached": False})
                return self._send(200, analyze_quality(i))

            if p == "/config":
                if "opacity" in q:
                    try:
                        CFG["opacity"] = max(0.25, min(1.0, float(q["opacity"][0])))
                    except ValueError:
                        pass
                    save_cfg()
                return self._send(200, dict(CFG))

            if p == "/hifi":
                if "on" in q:
                    on = q["on"][0] == "1"
                    subprocess.run([HIFI_BIN, "on" if on else "off"],
                                   capture_output=True, timeout=30)
                    MPV.restart(on)
                st = subprocess.run([HIFI_BIN, "status"], capture_output=True,
                                    text=True, timeout=5).stdout.strip()
                return self._send(200, {"ok": True, "status": st})

            if p == "/rescan":
                n = scan_library()
                return self._send(200, {"ok": True, "count": n})

            return self._send(404, {"error": "unknown"})
        except Exception as e:
            return self._send(500, {"error": str(e)})


PIDFILE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "musicd.pid")


def _shutdown_restore(*_a):
    """退出时一定要关掉直出。
    否则 hifi-mode 的静音状态会留着，USB DAC 也可能不在 PipeWire 里，
    结果是"关掉播放器后浏览器放视频没声音"。"""
    try:
        if MPV.hifi or hifi_state():
            env = dict(os.environ); env["HIFI_NO_PLAYER"] = "1"
            subprocess.run([HIFI_BIN, "off"], capture_output=True,
                           timeout=25, env=env)
            print("musicd: 退出，已关闭 HiFi 直出并恢复音频", flush=True)
    except Exception:
        pass
    try:
        os.unlink(PIDFILE)
    except OSError:
        pass


def main():
    import atexit
    import signal
    atexit.register(_shutdown_restore)
    for _sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        try:
            signal.signal(_sig, lambda *_a: sys.exit(0))
        except Exception:
            pass
    try:
        with open(PIDFILE, "w") as f:
            f.write(str(os.getpid()))
    except OSError:
        pass
    load_library()
    n = len(LIB["tracks"])
    print(f"musicd: 曲库 {n} 首，服务端口 {PORT}", flush=True)
    if "--rescan" in sys.argv:
        n = scan_library()
        print(f"musicd: 重新扫描完成，{n} 首", flush=True)
        return
    threading.Thread(target=spectrum_loop, daemon=True).start()
    threading.Thread(target=hifi_sync_loop, daemon=True).start()
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    srv.serve_forever()


if __name__ == "__main__":
    main()
