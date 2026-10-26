#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================
#  Google TV Home  一键设为小米电视默认桌面
#  运行端：安卓手机 Termux（adb 客户端跑在手机上）
#
#  用法一（管道，手机上不用传任何文件）：
#     curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome/sethome-tv.sh | TV=192.168.168.161 bash
#     （GitHub 直连就把前面的 ghfast.top/ 去掉）
#
#  用法二（本地跑）：
#     bash sethome-tv.sh                     # 交互式，提示输入 IP
#     bash sethome-tv.sh 192.168.168.161     # 直接带 IP
#     bash sethome-tv.sh 192.168.168.161 ./app.apk
#
#  环境变量:
#     TV=<IP[:端口]>   电视地址（管道模式下必须给）
#     APK=<路径>      指定用本地哪个 APK（不给就自动下载）
#     GH_FILE=<名>    换下载的文件名
#     GH_PATH=<路径>  换仓库路径
#
#  特点:
#    - 自动识别电视型号与 Android 版本
#    - 按"能力探测"选路，不只看版本号（厂商魔改机器版本与能力常不一致）
#    - 自动装 APK + 授权 + 设为默认 + 验证 + 兜底抢回
#    - 每一步都有回滚命令
# ==============================================================

set -u
PKG="io.kenny.tvhome"
ACT="$PKG/.MainActivity"
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
" "  curl -fsSL <脚本地址> | TV=192.168.168.161 bash"
  printf "%s
" "  bash sethome-tv.sh 192.168.168.161"
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

# ---------- 找 APK：本地优先，找不到就联网下载 ----------
# APK 下载地址：可用环境变量覆盖，方便换仓库/换包
GH_PATH="${GH_PATH:-kennyhn88/cleanyourtv/main/apk/io.kenny.tvhome}"
GH_FILE="${GH_FILE:-google-tv-home-test.apk}"
GH_RAW="${GH_RAW:-https://raw.githubusercontent.com/${GH_PATH}/${GH_FILE}}"
GH_MIRROR="${GH_MIRROR:-https://ghfast.top/${GH_RAW}}"

APK="${2:-${APK:-}}"
if [ -z "$APK" ]; then
  for cand in \
      "$SCRIPT_DIR"/google-tv-home-test.apk \
      "$SCRIPT_DIR"/google-tv-home-cn-keys-*.apk \
      "$SCRIPT_DIR"/google-tv-home*.apk \
      ./google-tv-home-test.apk \
      ./google-tv-home-cn-keys-*.apk \
      ./google-tv-home*.apk \
      "$HOME"/google-tv-home-test.apk \
      "$HOME"/google-tv-home-cn-keys-*.apk \
      "$HOME"/google-tv-home*.apk \
      /sdcard/Download/google-tv-home-test.apk \
      /sdcard/Download/google-tv-home-cn-keys-*.apk \
      /sdcard/Download/google-tv-home*.apk \
      ; do
    [ -f "$cand" ] && { APK="$cand"; break; }
  done
fi

# 本地没有 → 从 GitHub 下载（先直连，不行走 ghfast.top 加速）
if [ -z "$APK" ] || [ ! -f "$APK" ]; then
  command -v curl >/dev/null 2>&1 || die "本地没有 APK，且没有 curl 可用来下载。
请装 curl：pkg install curl
或手动下载后放到 $SCRIPT_DIR"

  APK="$SCRIPT_DIR/google-tv-home-test.apk"
  say "  本地没找到 APK，正在从 GitHub 下载 ..."
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
  [ "$DL_OK" -eq 1 ] || die "下载失败。请检查网络，或手动下载 APK 放到：
  $SCRIPT_DIR
下载地址：
  $GH_RAW
  $GH_MIRROR
（可用环境变量换源：GH_PATH=用户/仓库/分支/路径  GH_FILE=文件名）"
fi
ok "安装包：$APK"

# ==============================================================
# 1. 连电视
# ==============================================================
step "连接电视"

TVIP="${1:-${TV:-}}"
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

# 先看是否已经连着
DEV=""
if adb devices | awk '{print $1}' | grep -q "^${TVIP}:"; then
  DEV="$(adb devices | awk -v ip="$TVIP:" '$1 ~ "^"ip && $2=="device" {print $1; exit}')"
fi

if [ -z "$DEV" ]; then
  say "  扫描端口 ..."
  for port in 5555 5556 5557 5558 5559 5560 5037 8790; do
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

[ -n "$DEV" ] || die "连不上电视 $TVIP。请检查：
  1) 电脑/手机和电视在同一个路由器（同一网段）
  2) 电视已开 ADB 调试：设置 → 账号与安全 → ADB 调试
     （小米电视每次重启都会复位这个开关！）
  3) 电视上弹出的「允许 USB 调试」授权框要用遥控器点允许
  4) 电视 IP 是否正确"

ok "已连接 $DEV"
# 关键：adb 会把 stdin 透传给设备。在 "curl | bash" 管道模式下，
# stdin 是脚本本身，不切断的话 adb 会把脚本剩余内容全吸走，
# 导致脚本执行到一半静默消失。所以一律 </dev/null。
sh_() { adb -s "$DEV" shell "$@" </dev/null 2>/dev/null; }

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
#   3) 仍不生效，才停用系统桌面与兜底页（老 MIUI 才需要，且会动系统件）
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

if sh_ pm path "$PKG" | grep -q "^package:"; then
  say "  已安装，执行覆盖升级 ..."
  adb -s "$DEV" install -r "$APK" </dev/null || die "覆盖安装失败。
若提示 INSTALL_FAILED_UPDATE_INCOMPATIBLE，先执行：
  adb -s $DEV uninstall $PKG"
else
  say "  全新安装 ..."
  adb -s "$DEV" install "$APK" </dev/null || die "安装失败。检查 APK 是否与电视架构匹配。"
fi
ok "安装完成"

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

# 顺带把 ADB 开关守住（小米待机时会自己关掉）
if [ "$STRATEGY" = "role" ]; then
  sh_ settings put global adb_enabled 1 >/dev/null 2>&1
fi

# ==============================================================
# 5. 设为默认桌面
# ==============================================================
step "设为默认桌面"

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
        warn "两条命令都没生效，才动系统件（最后手段）"
        sh_ pm uninstall --user 0 com.mitv.tvhome >/dev/null
        sh_ pm disable-user --user 0 com.android.tv.settings >/dev/null
        sh_ pm disable-user --user 0 com.xiaomi.mitv.settings >/dev/null
        sh_ cmd package set-home-activity --user 0 "$ACT" >/dev/null
        ok "系统件已停用"
      fi
      ;;
  esac
else
  say "  停用系统桌面与兜底页（可回滚）..."
  sh_ pm uninstall --user 0 com.mitv.tvhome >/dev/null
  say "    com.mitv.tvhome 已停用"
  # 兜底页宿主：国内版可能藏在中文设置包里
  if sh_ pm path com.android.tv.settings | grep -q "^package:"; then
    sh_ pm disable-user --user 0 com.android.tv.settings >/dev/null
    say "    com.android.tv.settings 已停用（AOSP 兜底页宿主）"
  fi
  if sh_ pm path com.xiaomi.mitv.settings | grep -q "^package:"; then
    sh_ pm disable-user --user 0 com.xiaomi.mitv.settings >/dev/null
    say "    com.xiaomi.mitv.settings 已停用（国内版兜底页宿主）"
  fi
  sh_ cmd package set-home-activity --user 0 "$ACT" >/dev/null
  ok "传统方案已应用"
fi

# ==============================================================
# 6. 启用无障碍守卫（最稳的保险丝）
# ==============================================================
step "启用无障碍守卫"

GUARD="$PKG/.HomeGuardService"
CUR="$(sh_ settings get secure enabled_accessibility_services | tr -d '\r')"
case "$CUR" in
  *"$GUARD"*) ok "守卫已在无障碍列表中" ;;
  *)
    NEW="${CUR:+$GUARD:$CUR}"
    [ -z "$CUR" ] && NEW="$GUARD"
    sh_ settings put secure enabled_accessibility_services "$NEW" >/dev/null
    sh_ settings put secure accessibility_enabled 1 >/dev/null
    ok "已把守卫加入无障碍列表（系统桌面一冒头就被顶回）"
    ;;
esac

# ==============================================================
# 7. 验证
# ==============================================================
step "验证"

sh_ input keyevent 3 >/dev/null
sleep 3
FOCUS="$(sh_ dumpsys window | grep -iE 'mCurrentFocus|mFocusedApp' | tr -d '\r')"
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

# ==============================================================
# 8. 收尾
# ==============================================================
cat <<EOF

$(printf '%s' "$B")==========================================
  完成
==========================================$(printf '%s' "$N")

如果电视上还没自动切到 Google TV Home：
  方式 A（纯遥控器）
    打开桌面「设置」→ 「设为默认桌面」→ 确认
  方式 B（最稳）
    设置 → 无障碍 → 打开「Google TV Home 服务」

回滚命令（把系统桌面还原成原样）：
  adb -s $DEV shell cmd package install-existing com.mitv.tvhome
  adb -s $DEV shell pm enable com.android.tv.settings
  adb -s $DEV shell pm enable com.xiaomi.mitv.settings
  adb -s $DEV uninstall $PKG

提示：小米电视每次重启会复位 ADB 调试开关，需重新开启。
      本 App 拿到 WRITE_SECURE_SETTINGS 后会自动帮你把 ADB 开回来。
EOF
