#!/data/data/com.termux/files/usr/bin/bash
# SELFVER=20261027-1448
# ==============================================================
#  Google TV Home  一键设为 / 还原默认桌面（多品牌通用）
#  运行端：安卓手机 Termux（adb 客户端跑在手机上）
#  适用：小米 / 三星 / LG / 索尼 / TCL / 海信 / 创维 / 康佳 … 所有 Android TV
#
# ---------- 设为默认桌面 ----------
#  用法一（管道，手机上不用传任何文件）：
#     curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=192.168.168.161 bash
#     （GitHub 直连就把前面的 ghfast.top/ 去掉）
#
#  用法二（本地跑）：
#     bash tvhome.sh                        # 交互式，提示输入 IP
#     bash tvhome.sh 192.168.168.161        # 直接带 IP
#     bash tvhome.sh 192.168.168.161 ./app.apk
#     bash tvhome.sh 192.168.168.161:5555   # 指定端口
#
# ---------- 还原成电视原装桌面 ----------
#  用法一（管道）：
#     curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=192.168.168.161 bash -s restore
#     # 顺手把我们的 app 也卸掉（和 aerial 一个写法）：
#     curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=192.168.168.161 bash -s restore --uninstall
#
#  用法二（本地跑）：
#     bash tvhome.sh restore 192.168.168.161
#     bash tvhome.sh restore 192.168.168.161 --uninstall
#     bash tvhome.sh uninstall 192.168.168.161
#
# ---------- 修复（桌面被系统抢回去 / 守护没起来）----------
#     curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=192.168.168.161 bash -s repair
#
# ---------- 加固（治「按主页键先跳到原装桌面再弹回来」）----------
#     curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=192.168.168.161 bash -s harden
#
# ---------- 打开电视的「设置」（可选子页面）----------
#     curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=192.168.168.161 bash -s settings
#     # 进子页面：settings accessibility / apps / about / wifi / security / date
#
#  环境变量:
#     TV=<IP[:端口]> 电视地址（管道模式下必须给）
#     APK=<路径>      指定用本地哪个 APK（不给就自动下载）
#     GH_FILE=<名>    换下载的文件名
#     GH_PATH=<路径>  换仓库路径
#     NO_CLEAR=1      只接管、不清场（保留电视原装桌面，默认会清）
#     KEEP_MIUI_SETTINGS=1  保留小米的中文设置包（右上角「设置」还要用就加这个）
#     FORCE_CLEAR=1   连第三方桌面一起清（默认只清系统桌面 + 兜底页宿主，保留第三方）
#
#  特点:
#    - 自动识别电视型号与 Android 版本
#    - 按"能力探测"选路，不只看版本号（厂商魔改机器版本与能力常不一致）
#    - 自动装 APK + 授权 + 设为默认 + 清场 + 验证 + 兜底抢回
#    - 不硬编码任何品牌包名：系统桌面靠动态探测，各品牌通吃
#    - 支持 restore / uninstall / repair / harden 一条命令
#    - 每一步都有回滚命令
# ==============================================================

set -u
PKG="io.kenny.tvhome"
ACT="$PKG/.MainActivity"
GUARD_SVCS="$PKG/.HomeGuardService $PKG/.SettingsKey $PKG/.YtKeyService"
NOTIF_LS="$PKG/.MediaListener $PKG/.RevivalListener"
# 本版版本号（跟文件头 "# SELFVER=" 保持一致，改一处就够）。
# 用于自更新比对：线上版本号跟这个不一样就自动换用新版。
VER="20261027-1448"

# ---------- 模式与参数解析 ----------
#   install   （默认）装上并设为默认桌面
#   restore   交回电视原装桌面，App 保留
#   uninstall 交回电视原装桌面，并卸载 App
#   repair    修复：桌面被系统抢回时，重新拉起守护
#   harden    加固：清场（干掉原装桌面）+ 重设默认 + 重挂守卫，不重装 App
#   settings  打开电视的「设置」（可选子页面）
# 也支持 aerial 那种写法： restore --uninstall
MODE="install"
UNINSTALL=0
A1=""     # 第一个位置参数（通常是电视 IP）
A2=""     # 第二个位置参数（通常是 APK 路径 / settings 子页面）
SUB=""    # settings 模式的子页面
_i=0
# 判断一个词长得像不像 IP（192.168.1.5 / 192.168.1.5:5555 / 127.0.0.1）
# 判据：去掉可选的 ":端口" 后，剩下的必须是纯数字点，且至少一个点。
looks_like_ip() {
  _t="${1%%:*}"                 # 去掉 :端口
  case "$_t" in
    *[!0-9.]*) return 1 ;;      # 含非数字非点 → 不是 IP
    *.*)       return 0 ;;      # 至少一个点 → 像 IP
    *)         return 1 ;;      # 没有点 → 不是 IP
  esac
}
for _a in "$@"; do
  case "$_a" in
    restore)   MODE="restore" ;;
    uninstall) MODE="restore"; UNINSTALL=1 ;;
    repair)    MODE="repair" ;;
    harden)    MODE="harden" ;;
    install)   MODE="install" ;;
    settings)  MODE="settings" ;;
    accessibility|apps|about|wifi|security|date|storage|display|network)
                MODE="settings"; SUB="$_a" ;;
    --uninstall) UNINSTALL=1 ;;
    *)
      # 像 IP 的永远当地址，不当子页面 —— 这样
      #   bash -s settings 127.0.0.1:5555   （模式在前）
      #   bash -s 127.0.0.1:5555 settings   （模式在后）
      # 两种顺序都能用。
      if looks_like_ip "$_a"; then
        if   [ "$_i" -eq 0 ]; then A1="$_a"
        elif [ "$_i" -eq 1 ]; then A2="$_a"
        fi
        _i=$((_i + 1))
      # settings 模式下，非 IP 的第一个词就是子页面名（哪怕不认识）
      elif [ "$MODE" = "settings" ] && [ -z "$SUB" ]; then
        SUB="$_a"
        _i=$((_i + 1))
      else
        if   [ "$_i" -eq 0 ]; then A1="$_a"
        elif [ "$_i" -eq 1 ]; then A2="$_a"
        fi
        _i=$((_i + 1))
      fi
      ;;
  esac
done

# 管道执行（curl | bash）时 BASH_SOURCE 指向 bash 自己，取不到脚本真身。
# 这时把下载的 APK 放到 $HOME 下的固定目录，而不是当前目录。
SELF="${BASH_SOURCE[0]:-$0}"
case "$SELF" in
  */bash|*/sh|bash|sh) PIPED=1 ;;
  *) PIPED=0 ;;
esac
if [ "$PIPED" -eq 1 ]; then
  WORK_DIR="$HOME/.tvhome"
  mkdir -p "$WORK_DIR"
else
  WORK_DIR="$(cd "$(dirname "$SELF")" && pwd)"
fi

# ==============================================================
# 0.5 管道模式下自动取最新版（绕开加速站的 5 分钟缓存）
# ==============================================================
# ghfast.top 的响应头是 cache-control: max-age=300 —— 刚上传的新代码，
# 5 分钟内 curl 下来还是旧的（实测踩过：传了新版，curl 拿到的是旧版，
# 于是 "bash -s settings" 报"连不上电视 settings"，以为是网络问题）。
# 这里在脚本开头自己再拉一次，带时间戳强制绕过缓存；
# 拉到的内容跟当前跑的不一样，就用新的那份重跑。
if [ "$PIPED" -eq 1 ] && [ "${NO_SELFRESH:-0}" != "1" ] && command -v curl >/dev/null 2>&1; then
  _raw="${GH_RAW:-https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh}"
  _mir="${GH_MIRROR:-https://ghfast.top/${_raw}}"
  for _u in "${_raw}?t=$(date +%s)" "${_mir}?t=$(date +%s)"; do
    _tmp="$WORK_DIR/.selfupdate.$$"
    curl -fsSL --connect-timeout 8 --max-time 25 "$_u" -o "$_tmp" 2>/dev/null || { rm -f "$_tmp"; continue; }
    [ -s "$_tmp" ] || { rm -f "$_tmp"; continue; }
    # 防加速站返回错误页/HTML：必须是脚本
    if ! grep -q 'MODE=' "$_tmp" 2>/dev/null; then rm -f "$_tmp"; continue; fi
    # ⚠️ 绝对不能读 stdin 来比内容 —— 管道模式下 stdin 就是脚本本身，
    #    读它会把脚本剩余部分吃掉，脚本就静默消失了。
    #    改用版本号来比：文件头的 "# SELFVER=" 就是线上那版的版本号。
    #    线上没有这个标记 → 说明是老架构，一律换新的。
    _myver="$(sed -n 's/^# SELFVER=//p' "$_tmp" 2>/dev/null | head -1)"
    if [ "$_myver" = "$VER" ]; then
      rm -f "$_tmp"; break          # 线上就是本版，不用更新
    fi
    say "  发现更新版本（${VER} → ${_myver:-无版本号}），正在换用新版 ..."
    # 用新内容喂给 bash（stdin）。NO_SELFRESH=1 防止新版自己再触发自更新（递归）。
    NO_SELFRESH=1 bash -s -- "$@" < "$_tmp"
    _rc=$?
    rm -f "$_tmp"
    exit $_rc
  done
  unset _raw _mir _u _tmp _rc _myver
fi
SCRIPT_DIR="$WORK_DIR"

# ---------- 颜色（Termux 支持，非 TTY 时自动关闭）----------
if [ -t 1 ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[36m'; N=$'\033[0m'
else
  R=""; G=""; Y=""; B=""; N=""
fi
say()  { printf "%s\n" "$*"; }
ok()   { printf "%s✓%s %s\n" "$G" "$N" "$*"; }
warn() { printf "%s!%s %s\n" "$Y" "$N" "$*"; }
err()  { printf "%s✗%s %s\n" "$R" "$N" "$*"; }
step() { printf "\n%s==> %s%s\n" "$B" "$*" "$N"; }

die() { err "$*"; exit 1; }

# 多行提示用这个，避免在 die 的参数里写双引号（会破坏引号配对）
die_usage() {
  err "没指定电视 IP。"
  printf "%s
" "用法："
  printf "%s
" "  设为默认桌面："
  printf "%s
" "    curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=192.168.168.161 bash"
  printf "%s
" "  还原成原装桌面："
  printf "%s
" "    curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=192.168.168.161 bash -s restore"
  printf "%s
" "  还原并卸载（顺手把 app 也删掉）："
  printf "%s
" "    curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=192.168.168.161 bash -s restore --uninstall"
  printf "%s
" "  修复桌面被抢回："
  printf "%s
" "    curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=192.168.168.161 bash -s repair"
  printf "%s
" "  加固（治「先跳原装桌面再弹回来」，不重装 App）："
  printf "%s
" "    curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=192.168.168.161 bash -s harden"
  printf "%s
" "  打开电视的「设置」："
  printf "%s
" "    curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=192.168.168.161 bash -s settings"
  printf "%s
" "    # 直接进子页面（accessibility / apps / about / wifi / security / date / storage / display）"
  printf "%s
" "    curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=192.168.168.161 bash -s settings accessibility"
  exit 1
}

# ==============================================================
# 0. 环境检查
# ==============================================================
step "检查环境"

# 没有 adb 就自己装一份（跟 aerial 的做法一样）
if ! command -v adb >/dev/null 2>&1; then
  say "  没找到 adb，自动准备 platform-tools ..."
  command -v curl >/dev/null 2>&1 || die "没有 adb 也没有 curl。
在 Termux 里执行：  pkg install android-tools curl"

  PT_DIR="$HOME/.tvhome/platform-tools"
  if [ ! -x "$PT_DIR/adb" ]; then
    # Termux 跑在安卓上，用 linux 版 platform-tools
    mkdir -p "$PT_DIR"
    PT_URL="https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
    if ! curl -fL --connect-timeout 15 --max-time 300 --retry 2 \
            -o "$PT_DIR/pt.zip" "$PT_URL" 2>/dev/null; then
      # 国内可能连不上 dl.google.com，退回镜像
      PT_URL="https://mirrors.tuna.tsinghua.edu.cn/android/repository/platform-tools-latest-linux.zip"
      curl -fL --connect-timeout 15 --max-time 300 --retry 2 \
            -o "$PT_DIR/pt.zip" "$PT_URL" 2>/dev/null \
        || die "platform-tools 下载失败。请在 Termux 里执行：  pkg install android-tools"
    fi
    command -v unzip >/dev/null 2>&1 || die "没有 unzip，请执行：  pkg install unzip"
    unzip -q -o "$PT_DIR/pt.zip" -d "$PT_DIR" 2>/dev/null
    rm -f "$PT_DIR/pt.zip"
    [ -x "$PT_DIR/adb" ] && mv -f "$PT_DIR/adb" "$PT_DIR/adb.bin" 2>/dev/null
    [ -x "$PT_DIR/adb.bin" ] && mv -f "$PT_DIR/adb.bin" "$PT_DIR/adb" 2>/dev/null
  fi
  [ -x "$PT_DIR/adb" ] && export PATH="$PT_DIR:$PATH"
  command -v adb >/dev/null 2>&1 || die "adb 准备失败，请手动执行：  pkg install android-tools"
  ok "adb 已就绪（自动下载的 platform-tools）"
fi

adb version >/dev/null 2>&1 || die "adb 不可用，Termux 可能需要重启一次。"

ok "adb 可用：$(adb version 2>/dev/null | head -1)"

# ---------- 找 APK：显式指定 > 本地带版本号的包 > 联网下载 > 同名旧缓存兜底 ----------
# ⚠️ 缓存策略（踩过的坑）：
#    同名文件 "google-tv-home-test.apk" 当首选缓存是错的 —— 里面可能是上一版
#    （versionCode 更低），拿去覆盖电视上已装的新版会被系统拒绝：
#    INSTALL_FAILED_VERSION_DOWNGRADE → 脚本直接退出，接管步骤一步都没跑。
#    所以同名缓存只能当"下载失败时的兜底"，联网下载必须排在它前面。
GH_PATH="${GH_PATH:-kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome}"
GH_FILE="${GH_FILE:-google-tv-home-test.apk}"
GH_RAW="${GH_RAW:-https://raw.githubusercontent.com/${GH_PATH}/${GH_FILE}}"
GH_MIRROR="${GH_MIRROR:-https://ghfast.top/${GH_RAW}}"

if [ "$MODE" = "install" ]; then
APK="${A2:-${APK:-}}"
if [ -z "$APK" ]; then
  # 只认"带版本号"的本地包 —— 那才是用户自己挑好要装的那一份
  for cand in \
      "$SCRIPT_DIR"/google-tv-home-cn-keys-*.apk \
      "$SCRIPT_DIR"/google-tv-home-r*-*.apk \
      ./google-tv-home-cn-keys-*.apk \
      ./google-tv-home-r*-*.apk \
      "$HOME"/google-tv-home-cn-keys-*.apk \
      /sdcard/Download/google-tv-home-cn-keys-*.apk \
      ; do
    [ -f "$cand" ] && { APK="$cand"; break; }
  done
fi

# 联网下载（优先；同名旧缓存只在下载失败时兜底）
if [ -z "$APK" ] || [ ! -f "$APK" ]; then
  if command -v curl >/dev/null 2>&1; then
    APK="$SCRIPT_DIR/google-tv-home-test.apk"
    say "  正在从 GitHub 下载最新安装包 ..."
    DL_OK=0
    for u in "$GH_RAW" "$GH_MIRROR"; do
      case "$u" in
        *ghfast.top*) say "    尝试加速源 ghfast.top ..." ;;
        *)             say "    尝试 GitHub 直连 ..." ;;
      esac
      rm -f "$APK.part"
      if curl -fL --connect-timeout 15 --max-time 600 --retry 2 \
              -o "$APK.part" "$u" 2>/dev/null && [ -s "$APK.part" ]; then
        mv -f "$APK.part" "$APK"
        DL_OK=1
        ok "下载完成（$(du -h "$APK" | cut -f1)）"
        break
      fi
      rm -f "$APK.part"
    done
    if [ "$DL_OK" -eq 1 ]; then
      :
    elif [ -f "$APK" ]; then
      warn "下载失败，改用本地已有的旧缓存（可能不是最新版）"
    else
      die "下载失败。请检查网络，或手动下载 APK 放到：
  $SCRIPT_DIR
下载地址：
  $GH_RAW
  $GH_MIRROR
（可用环境变量换源：GH_PATH=用户/仓库/分支/路径  GH_FILE=文件名）"
    fi
  else
    # 没 curl：只能靠本地已有的包
    for cand in \
        "$SCRIPT_DIR"/google-tv-home-test.apk \
        "$SCRIPT_DIR"/google-tv-home*.apk \
        ./google-tv-home*.apk \
        "$HOME"/google-tv-home*.apk \
        /sdcard/Download/google-tv-home*.apk \
        ; do
      [ -f "$cand" ] && { APK="$cand"; break; }
    done
    [ -f "$APK" ] || die "本地没有 APK，且没有 curl 可用来下载。
请装 curl：pkg install curl
或手动下载后放到 $SCRIPT_DIR"
  fi
fi
ok "安装包：$APK"
fi   # end MODE = install

# ==============================================================
# 1. 连电视
# ==============================================================
step "连接电视"

TVIP="${A1:-${TV:-}}"
if [ -z "$TVIP" ]; then
  # 管道模式下 stdin 是脚本本身，read 读不到东西还可能吃掉脚本内容，
  # 所以这种情况直接要求给 TV= 参数，不做交互。
  if [ "$PIPED" -eq 1 ]; then
    die_usage
  fi
  printf "请输入电视 IP（小米电视一般在 192.168.168.x / 192.168.1.x）："
  read -r TVIP || die_usage
fi
[ -n "$TVIP" ] || die_usage

# 支持 IP:端口 形式（TV=192.168.1.20:5555），避免拼成 "ip:5555:5555"
TV_PORT=""
case "$TVIP" in
  *:*)
    TV_PORT="${TVIP##*:}"
    TVIP="${TVIP%:*}"
    case "$TV_PORT" in ''|*[!0-9]*) TV_PORT="" ;; esac
    ;;
esac

# 先看是否已经连着
DEV=""
if adb devices | awk '{print $1}' | grep -q "^${TVIP}:"; then
  DEV="$(adb devices | awk -v ip="$TVIP:" '$1 ~ "^"ip && $2=="device" {print $1; exit}')"
fi

if [ -z "$DEV" ]; then
  say "  扫描端口 ..."
  # 绝大多数 Android TV 用 5555；其余是各家 / 不同固件的常见调试端口
  PORTS="5555 5556 5557 5558 5559 5560 5554 5037 8790"
  # 用户显式指定了端口，就只试那一个
  [ -n "$TV_PORT" ] && PORTS="$TV_PORT"
  for port in $PORTS; do
    adb connect "$TVIP:$port" </dev/null >/dev/null 2>&1
    sleep 0.4
    st="$(adb -s "$TVIP:$port" get-state 2>/dev/null)"
    if [ "$st" = "device" ]; then DEV="$TVIP:$port"; break; fi
  done
fi

if [ -z "$DEV" ]; then
  # 最后再试一次主端口（有些电视要等几秒才起 adbd）
  sleep 2
  adb connect "$TVIP:5555" </dev/null >/dev/null 2>&1
  sleep 2
  st="$(adb -s "$TVIP:5555" get-state 2>/dev/null)"
  [ "$st" = "device" ] && DEV="$TVIP:5555"
fi

# ⚠️ 用户把模式名当成 IP 传进来了（例如旧版脚本 + "settings"）。
#    这时它不是网络不通，而是"这个版本还不认识这个模式"——
#    得说清楚，不然用户会一直去查网络。
if [ -z "$DEV" ]; then
  case "$TVIP" in
    settings|repair|restore|uninstall|install|harden)
      die "「${TVIP}」是脚本的模式名，不是电视 IP。
你拉到的应该是旧版脚本 —— 新版才支持这个模式。

两种解法，任选一个：

【1】绕过脚本，直接用 adb（任何版本都能用，立刻生效）
  adb -s <电视IP>:5555 shell am start -a android.settings.SETTINGS
  adb -s <电视IP>:5555 shell am start -a android.settings.ACCESSIBILITY_SETTINGS

【2】重新拉最新版（注意加了 ?t= 时间戳，否则会命中加速站的旧缓存）
  curl -fsSL \"<脚本地址>?t=\$(date +%s)\" | TV=127.0.0.1:5555 bash -s ${TVIP}
"
      ;;
  esac
fi

[ -n "$DEV" ] || die "连不上电视 ${TVIP}。请检查：
  1) 电脑/手机和电视在同一个路由器（同一网段）
  2) 电视已开 ADB 调试（各家位置不同）：
       小米   设置 → 账号与安全 → ADB 调试
       三星   设置 → 支持 → 开发者选项 → ADB 调试
       LG     设置 → 常规 → 外部设备 → 设备连接 → ADB 调试
       索尼   设置 → 设备偏好设置 → 开发者选项 → USB 调试
       海信/TCL/创维  设置 → 设备偏好设置/系统 → 开发者选项 → ADB 调试
     （小米等品牌每次重启都会复位这个开关！）
  3) 电视上弹出的「允许 USB 调试」授权框要用遥控器点允许
  4) 电视 IP 是否正确；也可以指定端口：TV=192.168.1.20:5555"

ok "已连接 $DEV"
# 关键：adb 会把 stdin 透传给设备。在 "curl | bash" 管道模式下，
# stdin 是脚本本身，不切断的话 adb 会把脚本剩余内容全吸走，
# 导致脚本执行到一半静默消失。所以一律 </dev/null。
sh_() { adb -s "$DEV" shell "$@" </dev/null 2>/dev/null; }
# 整条命令作为一个参数交给设备端 shell（重定向、引号按原样传过去）
shraw() { adb -s "$DEV" shell "$1" </dev/null 2>/dev/null; }
# 当前真正在前台的窗口。
# ⚠️ 不能在整段 dumpsys 里搜包名：那里会留着历史记录，会把"没接管上"误判成"接管上了"。
#    只取最后一条非 null 的 mCurrentFocus。
current_focus() {
  _f="$(sh_ dumpsys window | grep -i 'mCurrentFocus=Window' | tail -1 | tr -d '\r')"
  if [ -z "$_f" ]; then
    _f="$(sh_ dumpsys window | grep -i 'mFocusedApp=ActivityRecord' | tail -1 | tr -d '\r')"
  fi
  printf '%s' "$_f"
}

# ==============================================================
# 1.2 清场工具（install / repair / harden 共用）
# ---------------------------------------------------------------
# 为什么要清场（思路来自 wangrongding/tv-fresh 的实测结论）：
#   很多厂商固件不会把 HOME 干净地让给第三方桌面：
#     · 原装桌面（小米 com.mitv.tvhome）自带更高的 intent 优先级，
#       实体遥控器的主页键会先把它启动起来，再由我们的无障碍守卫顶回来 ——
#       用户看到的就是「先跳到原装桌面 → 又弹回自制桌面」。
#     · 系统兜底页（FallbackHome）在「解析不出桌面」时会接管并反复重试，形成黑屏死循环。
#   tv-fresh 的解法是「把竞争者清场，让目标桌面唯一化」，这个思路是对的。
#
#  但 tv-fresh 的两条命令不能照抄 —— 它们的实测机型是 MiTV-ASTP0 / Android 9，
#  在 MiTV-MFTR0 / Android 14（161 实测）上两条都不成立：
#
#   ① pm uninstall --user 0 com.mitv.tvhome
#      → 直接报 Failure [DELETE_FAILED_INTERNAL_ERROR]。
#      原因是它是 /vendor/app 的 priv-app，厂商做了保护，不许从用户侧卸载。
#      → 本脚本自动降级成 pm disable-user --user 0（同样可逆，
#        tv-fresh 的 restorehome 就是用 pm enable 还原的）。
#
#   ② pm disable-user --user 0 com.android.tv.settings
#      tv-fresh 说这包「只承载兜底页」，前提是他们机器上的中文设置在
#      com.xiaomi.mitv.settings。161 上角色正好反过来（实测）：
#         android.settings.SETTINGS             -> com.android.tv.settings/.MainSettings
#         android.settings.APPLICATION_SETTINGS -> com.android.tv.settings/.device.apps.AppsActivity
#         android.settings.WIFI_SETTINGS        -> com.android.tv.settings/.connectivity.NetworkActivity
#         android.settings.ACCESSIBILITY_SETTINGS-> com.android.tv.settings/.oemlink.AccessibilitySettingsActivity
#      所有标准设置页都由它提供，停掉它用户就进不了设置（实测：am start -a
#      android.settings.SETTINGS → "unable to resolve Intent"）。
#      而 com.xiaomi.mitv.settings 反而不接管任何标准设置 action，
#      它只有 .entry.MainActivity（MIUI 自家设置界面）和 .entry.FallbackHome（兜底页）。
#      → 所以这一条必须按「这台机器上谁才是设置本体」动态判断，绝不能写死包名。
#        确实想按 tv-fresh 原样来的，可以加 FORCE_CLEAR=1（脚本会先警告）。
# ==============================================================

# 我们动过的包，格式 "包名|动作"，动作 = uninstall / disable
DISABLED_LIST=""
ROLLBACK=""

# 记一笔，并生成对应的回滚命令
record_change() {
  _rp="$1"
  _ra="$2"
  [ -n "$_rp" ] || return 0
  DISABLED_LIST="${DISABLED_LIST} ${_rp}|${_ra}"
  case "$_ra" in
    uninstall) ROLLBACK="${ROLLBACK}  adb -s $DEV shell cmd package install-existing $_rp
" ;;
    disable)   ROLLBACK="${ROLLBACK}  adb -s $DEV shell pm enable --user 0 $_rp
" ;;
  esac
}

# 这台机器上的 HOME 候选（组件级，形如 包名/类名）
home_candidates() {
  sh_ cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null \
    | tr -d '\r' | sed 's/^[[:space:]]*//' \
    | grep -E '^[a-zA-Z0-9_.]+/[a-zA-Z0-9_.]+$' | sort -u
}

# 这台机器是不是有别的应用能接管标准设置 action（= 停掉这个包后用户还有没有设置可用）
settings_survivor() {
  for _a in android.settings.SETTINGS android.settings.APPLICATION_SETTINGS \
            android.settings.DEVICE_INFO_SETTINGS android.settings.WIFI_SETTINGS; do
    _h="$(sh_ cmd package query-activities --brief -a "$_a" 2>/dev/null \
           | tr -d '\r' | sed 's/^[[:space:]]*//' \
           | grep -E '^[a-zA-Z0-9_.]+/' | head -1 | cut -d/ -f1)"
    [ -n "$_h" ] || continue
    case "$_h" in
      "$1") ;;                 # 就是它 → 不算幸存者
      *) printf '%s' "$_h"; return 0 ;;
    esac
  done
  return 1
}

# 这个包在应用列表里有没有图标（有 = 用户看得见的应用，整包停掉会让人找不到它）
has_launcher_icon() {
  sh_ cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER 2>/dev/null \
    | tr -d '\r' | sed 's/^[[:space:]]*//' \
    | grep -E "^$1/" >/dev/null 2>&1
}

# 清掉一个竞争者（HOME 候选里的别人）
disable_if_exists() {
  _p="$1"
  [ -n "$_p" ] || return 0
  [ "$_p" = "$PKG" ] && return 0
  # 设置类包：
  #   com.xiaomi.mitv.settings —— 161 上真正在抢解析的兜底页就住在它里面
  #     （com.xiaomi.mitv.settings/.entry.FallbackHome，priority=-1000），
  #     禁掉它 resolve-activity 才认我们（实测）。默认禁，带 KEEP_MIUI_SETTINGS=1 可保留。
  #   com.android.tv.settings —— 这台电视的「设置」本体，停它系统的标准设置入口全断
  #     （实测 am start -a android.settings.SETTINGS → unable to resolve Intent），
  #     默认不碰；只有 FORCE_CLEAR=1 才动。
  case "$_p" in
    com.xiaomi.mitv.settings)
      if [ "${KEEP_MIUI_SETTINGS:-0}" = "1" ]; then
        say "    保留 ${_p}（KEEP_MIUI_SETTINGS=1）"
        return 0
      fi
      ;;
    com.android.tv.settings|com.android.settings)
      if [ "${ALLOW_SETTINGS_KILL:-0}" != "1" ]; then
        say "    跳过设置类包 ${_p}（停了系统的标准设置入口就全断了）"
        return 0
      fi
      ;;
  esac
  sh_ pm path "$_p" 2>/dev/null | grep -q "^package:" || return 1
  # 系统包 → 先试 pm uninstall --user 0（tv-fresh 的做法，可逆：install-existing 能恢复）
  #   厂商保护的分区包会失败 → 自动降级成整包禁用，同样可逆
  if sh_ pm list packages -s 2>/dev/null | tr -d '\r' | sed 's/package://' | grep -qx "$_p"; then
    _uo="$(sh_ pm uninstall --user 0 "$_p" 2>/dev/null)"
    case "$_uo" in
      *Success*)
        say "    已从当前用户卸载 ${_p}（系统包，可还原）"
        record_change "$_p" uninstall
        ;;
      *)
        if sh_ pm disable-user --user 0 "$_p" 2>/dev/null | grep -q "new state"; then
          say "    ${_p} 厂商不让卸载（DELETE_FAILED_INTERNAL_ERROR），改为整包禁用（可还原）"
          record_change "$_p" disable
        else
          warn "    ${_p} 清不掉（跳过）"
        fi
        ;;
    esac
  else
    # 第三方包 → 默认**不**禁用：
    #   · 第三方用 uninstall --user 0 不可逆（装不回来），禁掉风险大；
    #   · 实测第三方桌面（如 tv.glass.home）即便保留，HOME 键也稳定落回我们
    #     （role 机制优先认我们，PMS 也不会把第三方 priority 钳成负数），
    #     而禁用它只会让我们桌面上它的图标变成空框（包被禁用、banner 加载不出）。
    #   想连第三方桌面一起清，加 FORCE_CLEAR=1。
    if [ "${FORCE_CLEAR:-0}" = "1" ]; then
      if sh_ pm disable-user --user 0 "$_p" 2>/dev/null | grep -q "new state"; then
        say "    已停用 ${_p}（第三方包，FORCE_CLEAR=1）"
        record_change "$_p" disable
      else
        warn "    ${_p} 停用失败（跳过）"
      fi
    else
      say "    保留第三方包 ${_p}（不禁用；加 FORCE_CLEAR=1 可强制清除）"
    fi
  fi
  return 0
}

# 这台机器上所有 FallbackHome 兜底页组件
fallback_components() {
  sh_ dumpsys package 2>/dev/null | tr -d '\r' \
    | grep -oE '[a-zA-Z0-9_.]+/[a-zA-Z0-9_.]*[Ff]allback[Hh]ome[A-Za-z0-9_.]*' | sort -u
}

# 兜底页宿主处理（tv-fresh 说的"关键一步"）。
# ⚠️ 为什么这一步在某些机器上必须做（161 实测）：
#   MIUI 的 PMS 被打过补丁 —— HOME 解析会优先挑 priority<0 的兜底页，
#   不管首选记录写了谁。所以清场之后如果不处理兜底页，
#   `cmd package resolve-activity -a MAIN -c HOME` 仍然会解析到
#   com.xiaomi.mitv.settings/.entry.FallbackHome（priority=-1000），
#   而厂商代码（实体遥控器的主页键）走的就是这条解析路径 →
#   用户看到「先跳到小米原装桌面 → 再被守卫顶回」的闪烁。
#   tv-fresh 记录里"set-home-activity 返回 Success 但解析不认"就是这条规则。
#
# ⚠️ 这一刀的代价（161 实测，已知且按 tv-fresh 原意接受）：
#   ① com.xiaomi.mitv.settings 在 161 上**就是**那个兜底页的宿主（.entry.FallbackHome，priority=-1000）。
#      禁掉它，resolve-activity 才认我们，实体遥控器主页键才不再闪一下原装桌面。
#      代价：右上角「设置」按钮跳的就是这个包 → 会打不开；
#            我们自己桌面上属于这个包的图标冷启动后要等十来秒才出来（实测属正常，tv.glass.home 等第三方桌面照常显示）。
#      恢复命令在收尾里打印（adb -s <TV> shell pm enable --user 0 com.xiaomi.mitv.settings）。
#   ② com.android.tv.settings 在 161 上是 AOSP「设置」本体：
#      停掉它 → am start -a android.settings.SETTINGS 直接 "unable to resolve Intent"，
#      无线网络/应用管理/关于本机/无障碍全部打不开，我们 App 自己的
#      「系统设置」按钮（Settings.ACTION_SETTINGS）也会废掉。
#      tv-fresh 说停它安全，是因为他们机器上中文设置在 com.xiaomi.mitv.settings。
#   → 所以**默认禁 com.xiaomi.mitv.settings（治闪烁），但绝不碰 com.android.tv.settings**。
#      想保留右上角「设置」就加 KEEP_MIUI_SETTINGS=1（代价：闪烁可能回来）。
neutralize_fallback_host() {
  _fb="$(fallback_components)"
  if [ -z "${_fb// /}" ]; then
    say "    （这台机器没找到兜底页组件）"
    return 0
  fi
  for _fc in $_fb; do
    _fp="${_fc%%/*}"
    # ① 组件级：最精准，只干掉兜底页，不动设置本体
    if sh_ pm disable-user --user 0 "$_fc" 2>/dev/null | grep -q "new state"; then
      say "    已停用兜底页组件 ${_fc}（不动设置本体）"
      record_change "$_fc" disable
      continue
    fi
    # ② 组件级被系统拒绝（shell 无权停用系统包的组件，实测抛 SecurityException）
    case "$_fp" in
      com.xiaomi.mitv.settings)
        # 161 上真正在抢解析的兜底页就住在这个包里（.entry.FallbackHome，priority=-1000）。
        # 禁掉它，resolve-activity 才会认我们（实测：禁之前解析到兜底页，禁之后解析到我们）。
        # 代价（实测）：右上角「设置」跳的就是这个包 → 会打不开；
        #               桌面上的 App 图标在冷启动后要等十来秒才陆续出来。
        # 想留着它就加 KEEP_MIUI_SETTINGS=1。
        if [ "${KEEP_MIUI_SETTINGS:-0}" = "1" ]; then
          say "    保留 ${_fc}（KEEP_MIUI_SETTINGS=1）：右上角「设置」还能用，但抢解析的路没断"
          continue
        fi
        warn "    兜底页 ${_fc} 住在 MIUI 设置包里 → 整包停用 ${_fp}"
        warn "    ⚠️ 右上角「设置」会打不开（恢复：adb shell pm enable --user 0 ${_fp}）"
        warn "    ⚠️ 桌面上的 App 图标冷启动后会晚十来秒才出来（属正常）"
        disable_if_exists "$_fp"
        continue
        ;;
    esac
    _surv="$(settings_survivor "$_fp")"
    if [ -z "$_surv" ]; then
      say "    跳过 ${_fc}：停掉 ${_fp} 之后这台电视就没有能接管标准设置 action 的应用了"
      say "      （${_fp} 就是这台电视的「设置」本体，停掉用户就进不了设置）"
      continue
    fi
    if [ "${FORCE_CLEAR:-0}" = "1" ]; then
      warn "    FORCE_CLEAR=1 → 整包停用兜底页宿主 ${_fp}"
      warn "    ⚠️ 系统的标准设置入口会失效（设置由 ${_surv} 接管）"
      ALLOW_SETTINGS_KILL=1
      disable_if_exists "$_fp"
      ALLOW_SETTINGS_KILL=0
    else
      say "    兜底页 ${_fc} 组件级禁不掉（系统不给 shell 这个权限）"
      say "      它的宿主 ${_fp} 可以停（设置会由 ${_surv} 接管），代价是系统的标准设置入口失效"
      say "      想按 tv-fresh 原样来就加 FORCE_CLEAR=1 再跑一次本命令"
    fi
  done
}

# 清场总入口：把除我们之外的 HOME 竞争者全部清掉
# ⚠️ 调用前必须确认我们已经是默认桌面，否则清完场会黑屏。
clear_field() {
  say "  清场（让 Google TV Home 成为唯一桌面）..."
  _acts="$(home_candidates | grep -v "^${PKG}/")"
  if [ -z "${_acts// /}" ]; then
    say "    （已经没有别的 HOME 候选了）"
  else
    for _act in $_acts; do
      _p="${_act%%/*}"
      case "$_act" in
        *Fallback*|*fallback*) ;;   # 兜底页交给 neutralize_fallback_host 统一处理
        *) disable_if_exists "$_p" ;;
      esac
    done
  fi
  # 兜底页有可能不在候选列表里（priority 为负，解析不出桌面时才用）→ 单独扫一遍
  neutralize_fallback_host
  # 报告结果：还有谁在竞争 HOME
  _left="$(home_candidates | grep -v "^${PKG}/")"
  if [ -z "${_left// /}" ]; then
    ok "  清场完成：现在只剩我们一个桌面候选"
  else
    say "  清场后还在竞争 HOME 的："
    printf '%s\n' "$_left" | sed 's/^/    /'
  fi
}

# 系统现在认谁是默认桌面？（三路都查，别只查一路）
# ① HOME 角色持有者（Android 13+ 才有 get-role-holders）
# ② 首选记录里有没有我们
# ③ 系统解析 HOME 时是不是我们
is_default_home() {
  _h="$(sh_ cmd role get-role-holders --user 0 android.app.role.HOME 2>/dev/null | tr -d '\r')"
  case "$_h" in *"Unknown command"*) _h="" ;; esac
  if [ -z "$_h" ]; then
    _h="$(sh_ dumpsys role 2>/dev/null | grep -A3 'name=android.app.role.HOME' | grep holders= | tr -d '\r ')"
  fi
  case "$_h" in *"$PKG"*) return 0 ;; esac
  # 首选记录里有没有我们
  _p="$(sh_ dumpsys package 2>/dev/null | grep -A6 'Preferred Activities User 0' | grep -c "$PKG")"
  [ "${_p:-0}" -gt 0 ] && return 0
  # 最后问系统：HOME 现在解析到谁
  _r="$(sh_ cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null \
        | tr -d '\r' | sed 's/^[[:space:]]*//' | grep -E '^[a-zA-Z0-9_.]+/' | head -1)"
  case "$_r" in "$PKG/"*) return 0 ;; esac
  return 1
}

# 报告系统现在把 HOME 解析到谁。
# ⚠️ 这条路径和「按 HOME 键」不是一回事（161 实测）：
#   · 按 HOME 键 → 走 RoleManager（Android 13+ 写 mAlways=true）→ 认我们
#   · resolve-activity → 走 PMS 的候选排序 → MIUI 打过补丁，会优先挑
#     priority<0 的兜底页，不管首选记录写了谁
#   实体遥控器的主页键走哪条，取决于厂商自己的代码 —— 所以两条都要干净。
report_resolve() {
  _rn="$(sh_ cmd package resolve-activity -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tr -d '\r')"
  _rp="$(printf '%s\n' "$_rn" | grep -E '^[[:space:]]*packageName=' | head -1 | sed 's/.*=//')"
  _rcls="$(printf '%s\n' "$_rn" | grep -E '^[[:space:]]*name=' | head -1 | sed 's/.*=//')"
  _rpri="$(printf '%s\n' "$_rn" | grep -E '^priority=' | head -1 | sed 's/.*priority=//')"
  if [ -z "$_rp" ]; then
    # 老系统可能只认 --brief 的短格式
    _rb="$(sh_ cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null \
           | tr -d '\r' | sed 's/^[[:space:]]*//' | grep -E '^[a-zA-Z0-9_.]+/' | head -1)"
    if [ -n "$_rb" ]; then
      _rp="${_rb%%/*}"
      _rcls="${_rb#*/}"
    fi
  fi
  if [ -z "$_rp" ]; then
    warn "  系统解析 HOME 失败（这台机器的 cmd 可能不支持）"
    return 0
  fi
  say "  系统解析 HOME → ${_rp}${_rcls:+/${_rcls}}${_rpri:+ （priority=${_rpri}）}"
  case "$_rp" in
    "$PKG"*) ok "  解析正确：厂商代码走这条路径也只会找到我们" ;;
    *) warn "  解析到的不是我们 —— 实体遥控器主页键仍可能先跳过去再被顶回" ;;
  esac
}

# 如果电视上有「设置」包被禁用了，把恢复命令原样打出来（用户照抄就能恢复）
report_settings_state() {
  _hit=0
  for _p in com.xiaomi.mitv.settings com.android.tv.settings; do
    if sh_ pm list packages -d 2>/dev/null | tr -d '\r' | sed 's/package://' | grep -qx "$_p"; then
      _hit=1
      say "  ${_p} 目前是「已禁用」状态"
      say "    想恢复它，在电脑上（或手机 Termux 里）跑这一条："
      say "      adb -s $DEV shell pm enable --user 0 $_p"
      say "      （短写法：adb -s $DEV shell pm enable $_p）"
    fi
  done
  [ "$_hit" -eq 1 ] && say "    恢复后：右上角「设置」能用了，桌面图标也会立刻出来"
  return 0
}

# 把"我们动过哪些包"记到电视上（包一旦被停用，query-activities 就不再列出它，
# 光靠动态查询还原不回来）。格式：每行 "包名|动作"
save_disabled_list() {
  [ -n "${DISABLED_LIST// /}" ] || return 0
  shraw "rm -f /data/local/tmp/tvhome-disabled-pkgs"
  for _e in $DISABLED_LIST; do
    shraw "echo '$_e' >> /data/local/tmp/tvhome-disabled-pkgs"
  done
  ok "停用清单已记到电视上（以后 restore 能精确还原）"
}

# ==============================================================
# 1.5 打开电视的「设置」
# ==============================================================
if [ "$MODE" = "settings" ]; then
  step "打开电视的「设置」"

  # 子页面映射。只用 AOSP 标准 action —— 各家 ROM 都认这套，
  # 不用包名就不会因为品牌不同而失效。
  SUB="${SUB:-${A2:-}}"
  ACT=""
  case "$SUB" in
    ""|main)          ACT="android.settings.SETTINGS" ;;
    accessibility)    ACT="android.settings.ACCESSIBILITY_SETTINGS" ;;
    apps|app)         ACT="android.settings.APPLICATION_SETTINGS" ;;
    manage)           ACT="android.settings.MANAGE_APPLICATIONS_SETTINGS" ;;
    about|device)     ACT="android.settings.DEVICE_INFO_SETTINGS" ;;
    wifi|network)     ACT="android.settings.WIFI_SETTINGS" ;;
    security)         ACT="android.settings.SECURITY_SETTINGS" ;;
    date|time)        ACT="android.settings.DATE_SETTINGS" ;;
    storage)          ACT="android.settings.INTERNAL_STORAGE_SETTINGS" ;;
    display)          ACT="android.settings.DISPLAY_SETTINGS" ;;
    *)                ACT="" ;;
  esac

  if [ -z "$ACT" ]; then
    # 未知子页面 → 先回退到设置主界面
    warn "不认识的子页面「${SUB}」，改为打开设置主界面"
    ACT="android.settings.SETTINGS"
  fi

  OUT="$(adb -s "$DEV" shell am start -a "$ACT" </dev/null 2>&1 | tr -d '\r')"
  if printf '%s' "$OUT" | grep -q "Error"; then
    # 这台机器不支持这个 action → 退回设置主界面
    if [ "$ACT" = "android.settings.SETTINGS" ]; then
      die "连设置都打不开：
$OUT"
    fi
    warn "这台电视不支持「${SUB}」，改为打开设置主界面"
    adb -s "$DEV" shell am start -a android.settings.SETTINGS </dev/null >/dev/null 2>&1
    ACT="android.settings.SETTINGS"
  fi

  sleep 3
  FOCUS="$(current_focus)"
  ok "已打开：${ACT}"
  say "  当前前台："
  printf "%s\n" "$FOCUS" | sed 's/^/    /'

  cat <<EOF

$(printf '%s' "$B")==========================================
  设置已打开
==========================================$(printf '%s' "$N")

用遥控器就能操作了（用方向键 + OK）。

想直接进某个子页面，把名字跟在 settings 后面：
  ... | TV=$TVIP bash -s settings accessibility   # 无障碍（开桌面守卫）
  ... | TV=$TVIP bash -s settings apps            # 应用管理
  ... | TV=$TVIP bash -s settings about            # 关于本机 / 版本号
  ... | TV=$TVIP bash -s settings wifi             # 无线网络
  ... | TV=$TVIP bash -s settings security         # 安全 / 密码
  ... | TV=$TVIP bash -s settings date             # 日期与时间
  ... | TV=$TVIP bash -s settings storage          # 存储
  ... | TV=$TVIP bash -s settings display          # 显示
EOF
  exit 0
fi

# ==============================================================
# 1.6 修复模式：桌面被系统抢回去时，重新拉起守护
# ==============================================================
if [ "$MODE" = "repair" ]; then
  step "修复（重新拉起桌面守护）"

  if ! sh_ pm path "$PKG" | grep -q "^package:"; then
    die "电视上没装 Google TV Home，先跑一次安装。"
  fi

  # 让 app 自己把守卫和无障碍重新登记一遍
  sh_ am force-stop "$PKG" >/dev/null
  sleep 2
  sh_ am start -W -n "$ACT" >/dev/null 2>&1
  sleep 5

  # 角色还我们吗？
  HOLD="$(sh_ cmd role get-role-holders --user 0 android.app.role.HOME | tr -d '\r')"
  case "$HOLD" in *"Unknown command"*) HOLD="" ;; esac
  if [ -z "$HOLD" ]; then
    HOLD="$(sh_ dumpsys role | grep -A3 'name=android.app.role.HOME' | grep holders= | tr -d '\r ')"
  fi
  case "$HOLD" in
    *"$PKG"*) ok "HOME 角色还在我们手上：$HOLD" ;;
    *)
      warn "HOME 角色丢了，重新申请 ..."
      sh_ cmd role add-role-holder --user 0 android.app.role.HOME "$PKG" >/dev/null
      sh_ cmd package set-home-activity --user 0 "$ACT" >/dev/null
      ok "已重新申请"
      ;;
  esac

  # 无障碍守卫在不在？
  CUR="$(sh_ settings get secure enabled_accessibility_services | tr -d '\r')"
  [ "$CUR" = "null" ] && CUR=""
  REG=0
  case "$CUR" in
    *"$PKG/.HomeGuardService"*) ok "守卫在无障碍列表里" ;;
    *)
      warn "守卫不在无障碍列表里，重新登记 ..."
      NEW="${CUR:+$PKG/.HomeGuardService:$CUR}"
      [ -z "$CUR" ] && NEW="$PKG/.HomeGuardService"
      sh_ settings put secure enabled_accessibility_services "'$NEW'" >/dev/null
      sh_ settings put secure accessibility_enabled 1 >/dev/null
      ok "已重新登记（等系统绑定服务）"
      REG=1
      ;;
  esac

  # 清场：把还在跟原装桌面抢 HOME 的家伙清掉
  # 「按主页键先跳到原装桌面、再被守卫顶回来」就是没清场的症状。
  if is_default_home; then
    if [ "${NO_CLEAR:-0}" != "1" ]; then
      clear_field
      save_disabled_list
    else
      say "  NO_CLEAR=1 → 跳过清场"
    fi
  else
    warn "还没拿到默认桌面，先不清场（清场有黑屏风险）"
  fi

  # 按主页键验收
  if [ "$REG" -eq 1 ]; then
    sleep 5   # 给无障碍服务绑定的时间
    sh_ input keyevent 3 >/dev/null
    sleep 4
  fi
  sh_ input keyevent 3 >/dev/null
  sleep 6
  FOCUS="$(current_focus)"
  say "  按 HOME 键后的焦点："
  printf "%s\n" "$FOCUS" | sed 's/^/    /'
  case "$FOCUS" in
    *"$PKG"*) ok "桌面已接管" ;;
    *) warn "焦点还没落到我们的桌面。索尼 Android 9 等机型上模拟按键和实体遥控器结果可能不同，用实体遥控器再按一次主页键看看。" ;;
  esac
  report_resolve
  say ""
  say "  想改回电视原装桌面："
  say "    curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=$TVIP bash -s restore"
  say "    curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=$TVIP bash -s restore --uninstall"
  exit 0
fi

# ==============================================================
# 1.7 加固模式：治「按主页键先跳到原装桌面、再弹回来」
# ---------------------------------------------------------------
# 症状：实体遥控器按主页键，电视先闪一下小米原装桌面，再跳回我们的自制桌面。
# 原因（161 上实测到的）：
#   · 小米原装桌面 com.mitv.tvhome 还在，它的 HOME 优先级比兜底页高，
#     厂商代码（遥控器主页键）解析 HOME 时会先挑它 → 闪一下原装桌面；
#   · 我们的无障碍守卫监听到窗口变化，又把我们顶回来 → 于是「弹回」。
# 治法：把竞争者清掉（清场），让我们成为唯一候选。
# 本模式不重装 App，只做：确认默认桌面 → 清场 → 重挂守卫 → 验收。
# ==============================================================
if [ "$MODE" = "harden" ]; then
  step "加固（清场 + 重挂守卫）"

  if ! sh_ pm path "$PKG" | grep -q "^package:"; then
    die "电视上没装 Google TV Home，先跑一次安装。"
  fi

  # 1) 确认默认桌面还是我们，不是就重新拿
  if is_default_home; then
    ok "默认桌面已经是我们"
  else
    warn "默认桌面不是我们，重新申请 HOME 角色 ..."
    sh_ cmd role add-role-holder --user 0 android.app.role.HOME "$PKG" >/dev/null
    sleep 1
    sh_ cmd package set-home-activity --user 0 "$ACT" >/dev/null
    sleep 1
    if is_default_home; then
      ok "已重新拿到 HOME 角色"
    else
      warn "仍然拿不到默认桌面 —— 清场会有黑屏风险，这次不清场"
    fi
  fi

  # 2) 清场
  if is_default_home && [ "${NO_CLEAR:-0}" != "1" ]; then
    clear_field
    save_disabled_list
  elif [ "${NO_CLEAR:-0}" = "1" ]; then
    say "  NO_CLEAR=1 → 跳过清场"
  else
    warn "不是默认桌面，跳过清场"
  fi

  # 3) 重新拉起 App，让它把守卫重新登记一遍
  sh_ am force-stop "$PKG" >/dev/null
  sleep 2
  sh_ am start -W -n "$ACT" >/dev/null 2>&1
  sleep 4

  # 4) 守卫在不在？
  CUR="$(sh_ settings get secure enabled_accessibility_services | tr -d '\r')"
  [ "$CUR" = "null" ] && CUR=""
  case "$CUR" in
    *"$PKG/.HomeGuardService"*) ok "守卫已在无障碍列表里" ;;
    *)
      warn "守卫不在列表里，重新登记 ..."
      NEW="${CUR:+$PKG/.HomeGuardService:$CUR}"
      [ -z "$CUR" ] && NEW="$PKG/.HomeGuardService"
      sh_ settings put secure enabled_accessibility_services "'$NEW'" >/dev/null
      sh_ settings put secure accessibility_enabled 1 >/dev/null
      ok "已重新登记"
      ;;
  esac

  # 5) 验收：按主页键 + 看系统解析到谁
  sleep 5
  sh_ input keyevent 3 >/dev/null
  sleep 5
  FOCUS="$(current_focus)"
  say "  按 HOME 键后的焦点："
  printf "%s\n" "$FOCUS" | sed 's/^/    /'
  case "$FOCUS" in
    *"$PKG"*) ok "主页键直达 Google TV Home" ;;
    *) warn "焦点还没落到我们的桌面" ;;
  esac
  report_resolve

  cat <<EOF

$(printf '%s' "$B")==========================================
  加固完成
==========================================$(printf '%s' "$N")

已经清掉了跟原装桌面抢 HOME 的应用，主页键不会再闪到别处。

请用**实体遥控器**按一次主页键确认（adb 模拟的按键和实体遥控器走的可能不是同一条路）。

如果还是闪一下，加 FORCE_CLEAR=1 再跑一次（会连系统兜底页一起断）：
  ... | TV=$TVIP bash -s harden

想改回电视原装桌面（一条命令，可完整还原）：
  curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=$TVIP bash -s restore
EOF
  exit 0
fi

# ==============================================================
# 1.6 还原模式：把默认桌面交回给电视原装桌面
# ==============================================================
if [ "$MODE" = "restore" ]; then
  step "交还默认桌面（还原）"

  # ---- 先让我们自己闭嘴，否则它会立刻把角色/无障碍抢回去 ----
  # 顺序很重要：先撤 WRITE_SECURE_SETTINGS，app 就没法再自我复活；
  # force-stop 放到后面做（它会顺手清掉无障碍列表里的服务，
  # 放前面的话我们就看不到原来到底有哪些服务了）。
  sh_ pm revoke "$PKG" android.permission.WRITE_SECURE_SETTINGS >/dev/null 2>&1 \
    && ok "已收回 WRITE_SECURE_SETTINGS（app 不能再自己抢回无障碍/ADB）"

  # ---- 从无障碍列表里摘掉我们的 3 个服务，别的 App 的原样保留 ----
  CUR="$(sh_ settings get secure enabled_accessibility_services | tr -d '\r')"
  if [ -n "$CUR" ] && [ "$CUR" != "null" ]; then
    NEW="$(printf '%s' "$CUR" | tr ':' '\n' | grep -v "^${PKG}/" | grep -v '^$' | grep -v '^null$' | paste -sd: - 2>/dev/null)"
    if [ -z "$NEW" ]; then
      sh_ settings delete secure enabled_accessibility_services >/dev/null
      ok "已清空无障碍服务列表"
    elif [ "$NEW" != "$CUR" ]; then
      sh_ settings put secure enabled_accessibility_services "'$NEW'" >/dev/null
      ok "已从无障碍列表移除：HomeGuardService / SettingsKey / YtKeyService"
    else
      ok "无障碍列表里本来就没有我们的服务"
    fi
  else
    ok "无障碍列表本来就是空的"
  fi

  # ---- 通知监听也断掉（app 靠它开机复活自己）----
  for _nl in $NOTIF_LS; do
    sh_ cmd notification disallow_listener "$_nl" >/dev/null 2>&1
  done
  ok "已断开通知监听（app 不能再靠通知把自己拉起来）"

  # ---- 权限/appops 复位 ----
  sh_ appops set "$PKG" SYSTEM_ALERT_WINDOW default >/dev/null 2>&1
  sh_ appops set "$PKG" MANAGE_EXTERNAL_STORAGE default >/dev/null 2>&1
  sh_ appops set "$PKG" REQUEST_INSTALL_PACKAGES default >/dev/null 2>&1
  ok "已复位悬浮窗 / 存储 / 安装权限"

  # ---- 现在可以放心把进程停掉了（Android 会顺手清掉无障碍列表里的服务）----
  sh_ am force-stop "$PKG" >/dev/null
  ok "已停止 Google TV Home 进程"

  # ---- 屏保组件还原成系统默认 ----
  SC="$(sh_ settings get secure screensaver_components | tr -d '\r')"
  case "$SC" in
    "$PKG/"*)
      DEF="$(sh_ settings get secure screensaver_default_component | tr -d '\r')"
      [ -n "$DEF" ] && [ "$DEF" != "null" ] && sh_ settings put secure screensaver_components "'$DEF'" >/dev/null
      ok "屏保已还原成系统默认（${DEF}）"
      ;;
    *) ok "屏保没有被我们占用，无需还原" ;;
  esac

  # ---- 交出 HOME 角色 ----
  sh_ cmd role remove-role-holder --user 0 android.app.role.HOME "$PKG" >/dev/null 2>&1
  ok "已交出 HOME 角色"

  # ---- 海信 VIDAA：固件用 persist.vt.use_home_pkg 决定主页键去哪 ----
  VT_OLD="$(sh_ settings get global tvhome_vt_home_pkg | tr -d '\r')"
  if [ -n "$VT_OLD" ] && [ "$VT_OLD" != "null" ]; then
    sh_ setprop persist.vt.use_home_pkg "$VT_OLD" >/dev/null 2>&1
    sh_ settings delete global tvhome_vt_home_pkg >/dev/null
    ok "海信 VIDAA：home 包已改回 ${VT_OLD}"
  elif [ "$(sh_ getprop persist.vt.use_home_pkg | tr -d '\r')" = "$PKG" ]; then
    # 装的时候手动改过、没记原值的，按 VIDAA 通用值还原
    if sh_ pm path com.jamdeo.tv.vod 2>/dev/null | grep -q "^package:"; then
      sh_ setprop persist.vt.use_home_pkg com.jamdeo.tv.vod >/dev/null 2>&1
      ok "海信 VIDAA：home 包已改回 com.jamdeo.tv.vod"
    fi
  fi

  # ---- 把被停用的电视原装桌面全部启用回来 ----
  # 关键：包一旦被停用，query-activities 就不再列出它，
  # 所以不能只靠动态查询——我们安装时把停用清单记在电视上了，这里先读它。
  # 清单格式：每行 "包名|动作"，动作 = uninstall / disable（老版本只有包名，兼容）
  say "  启用电视原装桌面 ..."
  SAVED="$(sh_ cat /data/local/tmp/tvhome-disabled-pkgs 2>/dev/null | tr -d '\r')"
  REENABLED=""
  for _e in $SAVED; do
    _p="${_e%%|*}"
    _act="${_e#*|}"
    [ "$_act" = "$_e" ] && _act="auto"      # 老格式：只有包名
    [ "$_p" = "$PKG" ] && continue
    case "$_act" in
      uninstall) sh_ cmd package install-existing "$_p" >/dev/null 2>&1 ;;
      disable)   sh_ pm enable --user 0 "$_p" >/dev/null 2>&1 ;;
      *)         sh_ cmd package install-existing "$_p" >/dev/null 2>&1
                 sh_ pm enable --user 0 "$_p" >/dev/null 2>&1 ;;
    esac
    ok "已启用 ${_p}（当初被我们停用的）"
    REENABLED="${REENABLED} $_p"
  done
  # 兜底：扫当前被停用的包，把名字像桌面的也救回来
  for _p in $(sh_ pm list packages -d 2>/dev/null | tr -d '\r' | sed 's/package://' \
                | grep -iE 'launcher|home|settings' | grep -v "^${PKG}$"); do
    case "$REENABLED" in *" $_p") continue ;; esac
    sh_ cmd package install-existing "$_p" >/dev/null 2>&1
    sh_ pm enable --user 0 "$_p" >/dev/null 2>&1
    ok "已启用 ${_p}（被停用的桌面/设置）"
    REENABLED="${REENABLED} $_p"
  done
  # 各品牌兜底页宿主（可能被我们停用过）
  for _p in com.android.tv.settings com.mitv.tvhome com.xiaomi.mitv.settings; do
    case "$REENABLED" in *" $_p") continue ;; esac
    sh_ cmd package install-existing "$_p" >/dev/null 2>&1
    sh_ pm enable --user 0 "$_p" >/dev/null 2>&1
    case " $REENABLED " in *" $_p "*) ;; *) REENABLED="${REENABLED} $_p" ;; esac
  done

  # ---- 挑出电视原装桌面（我们之外的那个）----
  # 优先挑刚从清单里救回来的那个 —— 那才是当初被顶替的原装桌面
  STOCK=""
  _ACTS="$(sh_ cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null \
            | tr -d '\r' | sed 's/^[[:space:]]*//' \
            | grep -E '^[a-zA-Z0-9_.]+/[a-zA-Z0-9_.]+$' | grep -v "^${PKG}/")"
  for _p in $REENABLED; do
    for _c in $_ACTS; do
      case "$_c" in
        "$_p/"*) case "$_c" in *FallbackHome) continue ;; esac; STOCK="$_c"; break ;;
      esac
    done
    [ -n "$STOCK" ] && break
  done
  if [ -z "$STOCK" ]; then
    # 其次：系统自带且不是兜底页
    for _c in $_ACTS; do
      case "$_c" in *FallbackHome) continue ;; esac
      _p="${_c%%/*}"
      sh_ pm list packages -s 2>/dev/null | tr -d '\r' | sed 's/package://' | grep -qx "$_p" || continue
      STOCK="$_c"; break
    done
  fi
  if [ -z "$STOCK" ]; then
    # 最后：任意非兜底页候选
    for _c in $_ACTS; do
      case "$_c" in *FallbackHome) continue ;; esac
      STOCK="$_c"; break
    done
  fi

  # ---- 把首选记录指回原装桌面 ----
  if [ -n "$STOCK" ]; then
    sh_ cmd package set-home-activity --user 0 "$STOCK" >/dev/null 2>&1
    ok "首选桌面已指回：${STOCK}"
  else
    warn "没找到原装桌面，只交出了角色；请在电视上手动选一次原装桌面"
  fi
  # 清掉我们自己的首选记录
  sh_ pm clear-package-preferred-activities "$PKG" >/dev/null 2>&1
  # 清单用完了，删掉（下次再设桌面会重新写）
  shraw "rm -f /data/local/tmp/tvhome-disabled-pkgs"

  # ---- 卸载 / 保留 ----
  if [ "$UNINSTALL" -eq 1 ]; then
    adb -s "$DEV" uninstall "$PKG" </dev/null >/dev/null 2>&1 && ok "已卸载 Google TV Home" || warn "卸载失败，可到系统里手动卸载"
  else
    sh_ pm enable --user 0 "$PKG" >/dev/null 2>&1
    ok "App 保留在电视上（已不再接管桌面，随时可再装回来）"
  fi

  # ---- 验证 ----
  sh_ input keyevent 3 >/dev/null
  sleep 3
  FOCUS="$(current_focus)"
  say "  按 HOME 键后的焦点："
  printf "%s\n" "$FOCUS" | sed 's/^/    /'
  case "$FOCUS" in
    *"$PKG"*) warn "焦点还在我们的桌面上，可能需要重启电视一次" ;;
    *) ok "已交回电视原装桌面" ;;
  esac

  say ""
  say "  当前默认桌面："
  sh_ cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null \
    | tr -d '\r' | sed 's/^[[:space:]]*//' \
    | grep -E '^[a-zA-Z0-9_.]+/[a-zA-Z0-9_.]+$' | sed 's/^/    /'

  cat <<EOF

$(printf '%s' "$B")==========================================
  还原完成
==========================================$(printf '%s' "$N")

电视已经用回原装桌面。
如果画面还停在 Google TV Home：按一次 HOME 键，或重启电视。

再想装回来的话：
  curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=$TVIP bash

如果刚才没带 --uninstall（app 还留在电视上），现在想顺手删掉：
  curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=$TVIP bash -s restore --uninstall
EOF
  exit 0
fi

# ==============================================================
# 2. 读电视信息 + 能力探测
# ==============================================================
step "读取电视信息"

SDK="$(sh_ getprop ro.build.version.sdk | tr -d '\r')"
REL="$(sh_ getprop ro.build.version.release | tr -d '\r')"
MODEL="$(sh_ getprop ro.product.model | tr -d '\r')"
MFG="$(sh_ getprop ro.product.manufacturer | tr -d '\r')"

[ -n "$SDK" ] || die "读不到电视信息，连接可能已断。"

printf "  型号：%s %s\n  系统：Android %s (API %s)\n" "$MFG" "$MODEL" "$REL" "$SDK"

# ---- 能力探测：这套命令到底存不存在？（比看版本号可靠）----
# role 子命令是否真的可用（不能只 grep "role" 字样，
# Android 12 上 get-role-holders 会返回 "Unknown command"）
HAS_ROLE=0
ROLE_OUT="$(sh_ cmd role get-role-holders --user 0 android.app.role.HOME | tr -d '\r')"
if [ -n "$ROLE_OUT" ] && ! printf '%s' "$ROLE_OUT" | grep -q "Unknown command"; then
  HAS_ROLE=1
fi

# dumpsys role 里能否读到 HOME 角色（Android 10+ 才有这个角色）
HAS_ROLESVC=0
if sh_ dumpsys role 2>/dev/null | grep -q "name=android.app.role.HOME"; then
  HAS_ROLESVC=1
fi

# 系统里已有哪些 HOME 候选（只用于展示）
CAND="$(sh_ cmd package query-activities -a android.intent.action.MAIN -c android.intent.category.HOME | grep -oE 'packageName=[a-zA-Z0-9_.]+' | sed 's/packageName=//' | sort -u | tr '\n' ' ')"

say ""
say "  能力探测："
say "    RoleManager 角色机制 ......... $([ $HAS_ROLE -eq 1 ] && echo '可用' || echo '不可用')"
say "    dumpsys role 可读 HOME ....... $([ $HAS_ROLESVC -eq 1 ] && echo '可读' || echo '不可读')"
say "    已有 HOME 候选 ............... ${CAND:-（查询失败）}"
say ""

# 决定策略
# 判定策略：能读 role 持有者 → 走角色机制；否则退回传统方案。
# 注意：Android 12 有 dumpsys role 但没有 get-role-holders，
#      此时角色命令存在但读不到持有者，仍以传统方案 + 兜底更稳。
# 策略不是二选一，而是"能力探测 -> 逐级尝试 -> 验证 -> 兜底"：
#   1) 首选 role add-role-holder（Android 10+ 的 RoleManager，Android 13+ 最稳）
#   2) 退回 set-home-activity
#   3) 仍不生效，才停用系统桌面与兜底页（老系统才需要，且会动系统件）
# HAS_ROLE 只表示"读得到角色持有者"，读不到不代表 role 命令不可用，
# 所以真正的 role 尝试放在第 5 步做，失败会自动降级。
if [ "$HAS_ROLE" -eq 1 ]; then
  STRATEGY="role"        # 读得到持有者：Android 13+，最稳
elif [ "$HAS_ROLESVC" -eq 1 ]; then
  STRATEGY="role"        # 角色表里有 HOME：Android 10~12，role 命令大概率可用
else
  STRATEGY="legacy"      # 连 dumpsys role 都没有：真的老系统
fi

if [ "$STRATEGY" = "role" ]; then
  ok "策略：RoleManager（一条命令即可，不需要卸载任何系统应用）"
else
  warn "策略：传统方案（需停用系统桌面与兜底页，可回滚）"
fi

# ==============================================================
# 3. 安装 APK
# ==============================================================
step "安装 Google TV Home"

IS_INSTALLED=0
sh_ pm path "$PKG" | grep -q "^package:" && IS_INSTALLED=1

INSTALL_OUT=""
install_once() {
  if [ "$IS_INSTALLED" -eq 1 ]; then
    INSTALL_OUT="$(adb -s "$DEV" install -r "$APK" </dev/null 2>&1)"
  else
    INSTALL_OUT="$(adb -s "$DEV" install "$APK" </dev/null 2>&1)"
  fi
  printf '%s' "$INSTALL_OUT" | grep -q "Success"
}

if [ "$IS_INSTALLED" -eq 1 ]; then
  say "  已安装，执行覆盖升级 ..."
else
  say "  全新安装 ..."
fi

# 关键：接管（设角色 / 停用别的桌面）本身不依赖安装成功。
# 所以"装不上"不能直接退出 —— 只要电视上已经有我们这一版，就继续接管，
# 否则用户会看到"命令跑完了但桌面没换"的假象。
INSTALL_OK=0
if install_once; then
  INSTALL_OK=1
else
  case "$INSTALL_OUT" in
    *VERSION_DOWNGRADE*)
      # 这份安装包的 versionCode 比电视上已装的低 —— 电视上那版更新。
      # 绝不用 -d 降级覆盖（会把用户的好版本换掉），直接接管电视上那一版。
      if [ "$IS_INSTALLED" -eq 1 ]; then
        warn "这份安装包比电视上已装的旧（电视上是更新的版本），不降级覆盖"
        warn "直接接管电视上已安装的那一版 ..."
        INSTALL_OK=1
      else
        die "安装失败（版本被拒）：
$INSTALL_OUT"
      fi
      ;;
    *USER_RESTRICTED*)
      # 创维等固件会校验 adb 安装 → 临时关掉校验再试一次
      warn "固件在校验 adb 安装（创维等常见），临时关闭校验后重试 ..."
      VSAVE="$(sh_ settings get global verifier_verify_adb_installs | tr -d '\r')"
      sh_ settings put global verifier_verify_adb_installs 0 >/dev/null
      if install_once; then
        if [ -n "$VSAVE" ] && [ "$VSAVE" != "null" ]; then
          sh_ settings put global verifier_verify_adb_installs "$VSAVE" >/dev/null
        else
          sh_ settings delete global verifier_verify_adb_installs >/dev/null
        fi
        ok "关闭校验后安装成功（校验开关已还原）"
        INSTALL_OK=1
      else
        die "关掉校验后仍然装不上：
$INSTALL_OUT"
      fi
      ;;
    *UPDATE_INCOMPATIBLE*)
      die "覆盖安装失败：和电视上已装的版本签名不一致。
先卸载旧的再装：
  adb -s $DEV uninstall $PKG"
      ;;
    *DUPLICATE_PERMISSION*|*banned*|*VERIFICATION_FAILURE*)
      die "这台电视的固件拒绝安装桌面类 App：
$INSTALL_OUT

各家的已知解法：
  TCL     只能用电视自带的「多屏互动」推送安装（需要电视端确认）
  雷鸟/OPPO 等  换用电视自带的应用商店手动安装
  创维   先关掉安装校验：settings put global verifier_verify_adb_installs 0
  海信 VIDAA  部分机型只能用系统自带渠道
可以把它当普通 App 用（图标能进，但按主页键回不到它）。"
      ;;
    *)
      if [ "$IS_INSTALLED" -eq 1 ]; then
        warn "安装没成功（不影响接管，继续）：$INSTALL_OUT"
        INSTALL_OK=1
      else
        die "安装失败：
$INSTALL_OUT

检查一下：APK 是否与电视架构匹配（我们这个是纯 Java，arm64/armv7/x86_64 都行）。"
      fi
      ;;
  esac
fi
[ "$INSTALL_OK" -eq 1 ] && ok "安装完成"

# 性能编译：让电视上的首次启动更快（要几十秒，失败无所谓）
sh_ cmd package compile -m speed -f "$PKG" >/dev/null 2>&1 || true

# ==============================================================
# 4. 授权（关键：拿到 WRITE_SECURE_SETTINGS 才能自动守护）
# ==============================================================
step "授予权限"

if sh_ pm grant "$PKG" android.permission.WRITE_SECURE_SETTINGS | grep -q "Exception"; then
  warn "WRITE_SECURE_SETTINGS 授予失败（部分 ROM 限制），守卫功能会弱一些"
else
  ok "WRITE_SECURE_SETTINGS 已授予"
fi

sh_ appops set "$PKG" MANAGE_EXTERNAL_STORAGE allow >/dev/null 2>&1 \
  && ok "MANAGE_EXTERNAL_STORAGE 已允许" \
  || warn "MANAGE_EXTERNAL_STORAGE 设置失败（壁纸清理会受影响）"

# 顺带把 ADB 开关守住（部分品牌待机时会自己关掉）
if [ "$STRATEGY" = "role" ]; then
  sh_ settings put global adb_enabled 1 >/dev/null 2>&1
fi

# ==============================================================
# 5. 设为默认桌面
# ==============================================================
step "设为默认桌面"

# ---- 先设默认，再清场 ----
# ⚠️ 顺序不能反：清场之前必须先读回确认「我们已经是默认桌面」。
#    否则把竞争者都清掉、而我们自己又没被认成 HOME，电视上就一个能用的桌面都没有 = 黑屏。
if [ "$STRATEGY" = "role" ]; then
  say "  尝试 1/2：cmd role add-role-holder ..."
  sh_ cmd role add-role-holder --user 0 android.app.role.HOME "$PKG" >/dev/null
  sleep 1
  # 读回持有者，确认真的生效
  HOLD="$(sh_ cmd role get-role-holders --user 0 android.app.role.HOME | tr -d '\r')"
  case "$HOLD" in *"Unknown command"*) HOLD="" ;; esac
  if [ -z "$HOLD" ]; then
    HOLD="$(sh_ dumpsys role | grep -A3 'name=android.app.role.HOME' | grep holders= | tr -d '\r ')"
  fi
  case "$HOLD" in
    *"$PKG"*) ok "角色已授予：$HOLD" ;;
    *)
      warn "角色未生效，尝试 2/2：set-home-activity ..."
      sh_ cmd package set-home-activity --user 0 "$ACT" >/dev/null
      PREF="$(sh_ dumpsys package | grep -A6 'Preferred Activities User 0' | grep -c "$PKG")"
      if [ "${PREF:-0}" -gt 0 ]; then
        ok "首选桌面已登记"
      else
        warn "两条命令都没写进系统的首选记录"
      fi
      ;;
  esac
else
  say "  老系统没有 HOME 角色机制，走传统方案（set-home-activity + 清场）..."
  sh_ cmd package set-home-activity --user 0 "$ACT" >/dev/null
fi

# ---- 读回：现在系统认谁是默认桌面？（is_default_home 见上方共用工具区）----
if is_default_home; then
  ok "已确认默认桌面是我们，可以清场"
  CAN_CLEAR=1
else
  warn "还没确认拿到默认桌面，直接清场有黑屏风险"
  warn "先只登记首选记录，然后再判断 ..."
  sh_ cmd package set-home-activity --user 0 "$ACT" >/dev/null
  sleep 1
  if is_default_home; then
    ok "首选记录已生效，可以清场"
    CAN_CLEAR=1
  else
    warn "仍然拿不到默认桌面 —— 这次不清场（宁可留着原装桌面，也不能黑屏）"
    CAN_CLEAR=0
  fi
fi

# ---- 清场 ----
# 清场是治「按主页键先跳到原装桌面、再被我们的守卫顶回来」的正手。
# 做法参考 tv-fresh：把竞争者清掉，让目标桌面成为唯一候选。
if [ "$CAN_CLEAR" -eq 1 ] && [ "${NO_CLEAR:-0}" != "1" ]; then
  clear_field
elif [ "${NO_CLEAR:-0}" = "1" ]; then
  say "  NO_CLEAR=1 → 跳过清场（保留电视原装桌面）"
else
  say "  跳过清场"
fi

# 把"我们停用了哪些包"记在电视上。
# 原因：包一旦被停用，query-activities 就再也不列出它，
# 光靠动态查询还原不回来 —— 有了这份清单，restore 才能精确还原。
save_disabled_list

# ---- 海信 VIDAA：固件用 persist.vt.use_home_pkg 决定主页键去哪 ----
# 先把原值记下来（还原时要写回去），再改成我们的包名
VT_HOME="$(sh_ getprop persist.vt.use_home_pkg | tr -d '\r')"
if [ -n "$VT_HOME" ] && [ "$VT_HOME" != "null" ] && [ "$VT_HOME" != "$PKG" ]; then
  sh_ settings put global tvhome_vt_home_pkg "'$VT_HOME'" >/dev/null
  sh_ setprop persist.vt.use_home_pkg "$PKG" >/dev/null 2>&1 \
    && ok "海信 VIDAA：home 包已改成我们（原值 ${VT_HOME} 已记下，可还原）"
fi

# ==============================================================
# 6. 启用无障碍守卫（最稳的保险丝）
# ==============================================================
step "启用无障碍守卫"

GUARD="$PKG/.HomeGuardService"
CUR="$(sh_ settings get secure enabled_accessibility_services | tr -d '\r')"
# ⚠️ settings get 对"没设置过的键"返回字符串 null，不是空串。
#    不当空值处理的话，写回去就成了 "xxx:null"，守卫服务会绑定失败。
[ "$CUR" = "null" ] && CUR=""
case "$CUR" in
  *"$GUARD"*) ok "守卫已在无障碍列表中" ;;
  *)
    NEW="${CUR:+$GUARD:$CUR}"
    [ -z "$CUR" ] && NEW="$GUARD"
    sh_ settings put secure enabled_accessibility_services "'$NEW'" >/dev/null
    sh_ settings put secure accessibility_enabled 1 >/dev/null
    ok "已把守卫加入无障碍列表（系统桌面一冒头就被顶回）"
    ;;
esac

# 无障碍服务要进程在才会绑定。有的固件不会自动把 app 拉起来，
# 这里显式启动一次，守卫才会真正跑起来。
sh_ am start -W -n "$ACT" >/dev/null 2>&1
sleep 3

# ==============================================================
# 7. 验证
# ==============================================================
step "验证"

sh_ input keyevent 3 >/dev/null
sleep 5
FOCUS="$(current_focus)"
# 有的固件上守护启动得慢，第二次按主页键才接管（aerial 的做法）
case "$FOCUS" in
  *"$PKG"*) : ;;
  *)
    sleep 5
    sh_ input keyevent 3 >/dev/null
    sleep 5
    FOCUS="$(current_focus)"
    ;;
esac
say "  按 HOME 键后的焦点："
printf "%s\n" "$FOCUS" | sed 's/^/    /'

case "$FOCUS" in
  *"$PKG"*) ok "桌面已接管，HOME 键直达 Google TV Home" ;;
  *) warn "焦点还没落到我们的桌面。若电视上弹了选择框，用遥控器选 Google TV Home。" ;;
esac

echo ""
say "  默认桌面持有者："
if [ "$HAS_ROLE" -eq 1 ]; then
  sh_ cmd role get-role-holders --user 0 android.app.role.HOME | sed 's/^/    /'
elif [ "$HAS_ROLESVC" -eq 1 ]; then
  sh_ dumpsys role | grep -A3 "name=android.app.role.HOME" | sed 's/^/    /'
else
  sh_ dumpsys package | grep -A6 "Preferred Activities User 0" | sed 's/^/    /'
fi
report_resolve
report_settings_state   # 若禁用了设置类包，提示如何恢复

# ==============================================================
# 8. 收尾
# ==============================================================
# 回滚命令已在 disable_if_exists 里按类型生成好（系统包 install-existing / 第三方 pm enable）
cat <<EOF

$(printf '%s' "$B")==========================================
  完成
==========================================$(printf '%s' "$N")

如果电视上还没自动切到 Google TV Home：
  方式 A（纯遥控器）
    打开桌面「设置」→ 「设为默认桌面」→ 确认
  方式 B（最稳）
    设置 → 无障碍 → 打开「Google TV Home 服务」

请用**实体遥控器**按一次主页键确认（adb 模拟的按键和实体遥控器可能走的不是同一条路）。
如果还是先闪一下别家桌面，加 FORCE_CLEAR=1 再跑一次（会连系统兜底页一起断）：
  curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=$TVIP bash -s harden

想改回电视原装桌面（一条命令，可完整还原）：
  curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=$TVIP bash -s restore

  顺手把 app 也卸掉（还原 + 卸载，一条命令）：
  curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=$TVIP bash -s restore --uninstall

  桌面被系统抢回去了，用这个修：
  curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/tvhome.sh | TV=$TVIP bash -s repair

回滚命令（把系统桌面还原成原样）：
$ROLLBACK  adb -s $DEV shell uninstall $PKG

提示：部分品牌（如小米）每次重启会复位 ADB 调试开关，需重新开启。
      本 App 拿到 WRITE_SECURE_SETTINGS 后会自动帮你把 ADB 开回来。
EOF
