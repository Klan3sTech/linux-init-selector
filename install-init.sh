#!/bin/sh
#
# install-init.sh
# Помощник по установке альтернативных init-систем для init-selector.
#
# Скрипт не превращает выбранную init-систему в основную init системы.
# Он только устанавливает пакеты/бинарники, после чего нужно заново запустить
# ./install.sh, чтобы init-selector обнаружил новые пути и пересобрал initramfs.
#
# POSIX sh.
#

set -e

# Цвета включаем только на интерактивном терминале.
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN=''
    YELLOW=''
    RED=''
    CYAN=''
    BOLD=''
    NC=''
fi

log()   { printf "%b\n" "${GREEN}[+]${NC} $*"; }
warn()  { printf "%b\n" "${YELLOW}[!]${NC} $*"; }
error() { printf "%b\n" "${RED}[x]${NC} $*" >&2; }
info()  { printf "%b\n" "${CYAN}[i]${NC} $*"; }

if [ "$(id -u)" -ne 0 ]; then
    error "Запустите скрипт от имени root: sudo ./install-init.sh"
    exit 1
fi

printf "\n%b\n" "${BOLD}=== Помощник установки init-систем ===${NC}"
echo "Проект: init-selector"
echo

# ==========================================
# 1. Определение дистрибутива и пакетного менеджера
# ==========================================
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID=$(printf '%s' "$ID" | tr '[:upper:]' '[:lower:]')
        DISTRO_NAME=${NAME:-Linux}
        DISTRO_VERSION=${VERSION_ID:-unknown}
    else
        DISTRO_ID="unknown"
        DISTRO_NAME="Unknown Linux"
        DISTRO_VERSION="unknown"
    fi
}

detect_pkg() {
    PKG_MANAGER=""
    PKG_UPDATE=""
    PKG_INSTALL=""

    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt-get update"
        PKG_INSTALL="apt-get install -y"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf makecache"
        PKG_INSTALL="dnf install -y"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
        PKG_UPDATE="pacman -Sy"
        PKG_INSTALL="pacman -S --noconfirm"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        PKG_UPDATE="apk update"
        PKG_INSTALL="apk add"
    elif command -v xbps-install >/dev/null 2>&1; then
        PKG_MANAGER="xbps"
        PKG_UPDATE="xbps-install -S"
        PKG_INSTALL="xbps-install -y"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER="zypper"
        PKG_UPDATE="zypper refresh"
        PKG_INSTALL="zypper install -y"
    elif command -v emerge >/dev/null 2>&1; then
        PKG_MANAGER="emerge"
        PKG_UPDATE="emerge --sync"
        PKG_INSTALL="emerge -q"
    fi
}

detect_distro
detect_pkg

log "Обнаружено: $DISTRO_NAME ($DISTRO_ID $DISTRO_VERSION)"
if [ -n "$PKG_MANAGER" ]; then
    log "Пакетный менеджер: $PKG_MANAGER"
else
    warn "Поддерживаемый пакетный менеджер не найден. Будет доступна только сборка из исходников."
fi
echo

# ==========================================
# 2. Список init-систем
# ==========================================
init_desc() {
    case "$1" in
        openrc)   echo "OpenRC — зависимостный init/service manager, популярен в Gentoo/Alpine/Artix" ;;
        runit)    echo "runit — минималистичный и быстрый supervision-based init" ;;
        dinit)    echo "dinit — современный компактный init с зависимостями сервисов" ;;
        sysvinit) echo "SysVinit — классический /sbin/init с /etc/inittab" ;;
        s6)       echo "s6-linux-init — init на базе s6 supervision suite" ;;
        shepherd) echo "GNU Shepherd — init/service manager из экосистемы GNU/Guix" ;;
        finit)    echo "Finit — небольшой Fast init для embedded/обычных систем" ;;
        sinit)    echo "sinit — сверхминимальный init от suckless" ;;
        epoch)    echo "Epoch — альтернативный компактный init" ;;
        *)        echo "$1" ;;
    esac
}

source_supported() {
    case "$1" in
        runit|dinit|sinit) return 0 ;;
        *) return 1 ;;
    esac
}

# Список — это практическая подсказка, а не гарантия наличия пакета в каждом
# релизе. Если пакетный способ не сработает, для runit/dinit/sinit будет
# предложена сборка из исходников.
get_available_inits() {
    case "$DISTRO_ID" in
        debian|ubuntu|devuan|linuxmint|kali|pop|elementary)
            echo "openrc runit dinit sysvinit s6 shepherd finit"
            ;;
        artix)
            echo "openrc runit dinit s6 sysvinit shepherd finit sinit"
            ;;
        arch|manjaro|endeavouros|garuda)
            echo "openrc runit dinit s6 sysvinit shepherd finit sinit"
            ;;
        gentoo)
            echo "openrc runit dinit sysvinit s6 shepherd finit sinit"
            ;;
        alpine)
            echo "openrc runit dinit s6 finit sinit"
            ;;
        void)
            echo "runit dinit s6 openrc shepherd finit sinit"
            ;;
        opensuse*|suse*)
            echo "openrc runit dinit s6 shepherd finit"
            ;;
        fedora|rhel|centos|rocky|almalinux|ol)
            echo "runit dinit s6 shepherd finit sinit"
            ;;
        *)
            echo "openrc runit dinit sysvinit s6 shepherd finit sinit"
            ;;
    esac
}

AVAILABLE_INITS=$(get_available_inits)

printf "%b\n\n" "${BOLD}Доступные варианты для установки:${NC}"

i=1
for init_name in $AVAILABLE_INITS; do
    printf "  %s) %s\n" "$i" "$(init_desc "$init_name")"
    eval "MENU_$i=$init_name"
    i=$((i + 1))
done
printf "  %s) Отмена\n" "$i"
CANCEL=$i

echo
printf "Выберите номер: "
read -r choice

if [ "$choice" = "$CANCEL" ] || [ -z "$choice" ]; then
    log "Отмена."
    exit 0
fi

eval "CHOSEN=\$MENU_$choice"
if [ -z "$CHOSEN" ]; then
    error "Неверный выбор."
    exit 1
fi

echo
log "Вы выбрали: ${BOLD}$CHOSEN${NC}"
warn "Установка бинарников не гарантирует готовую конфигурацию сервисов."
warn "Перед реальной загрузкой обязательно проверьте выбранную init-систему в VM."
echo

# ==========================================
# 3. Пакеты для разных менеджеров
# ==========================================
pkg_names_for_init() {
    case "$PKG_MANAGER:$1" in
        apt:openrc)    echo "openrc openrc-init" ;;
        apt:runit)     echo "runit runit-init" ;;
        apt:dinit)     echo "dinit" ;;
        apt:sysvinit)  echo "sysvinit-core sysvinit-utils" ;;
        apt:s6)        echo "s6 s6-rc s6-linux-init" ;;
        apt:shepherd)  echo "shepherd" ;;
        apt:finit)     echo "finit" ;;

        pacman:openrc)    echo "openrc" ;;
        pacman:runit)     echo "runit" ;;
        pacman:dinit)     echo "dinit" ;;
        pacman:sysvinit)  echo "sysvinit" ;;
        pacman:s6)        echo "s6 s6-rc s6-linux-init" ;;
        pacman:shepherd)  echo "shepherd" ;;
        pacman:finit)     echo "finit" ;;
        pacman:sinit)     echo "sinit" ;;

        apk:openrc)    echo "openrc" ;;
        apk:runit)     echo "runit" ;;
        apk:dinit)     echo "dinit" ;;
        apk:s6)        echo "s6 s6-rc s6-linux-init" ;;
        apk:finit)     echo "finit" ;;
        apk:sinit)     echo "sinit" ;;

        xbps:openrc)   echo "openrc" ;;
        xbps:runit)    echo "runit" ;;
        xbps:dinit)    echo "dinit" ;;
        xbps:s6)       echo "s6 s6-rc s6-linux-init" ;;
        xbps:shepherd) echo "shepherd" ;;
        xbps:finit)    echo "finit" ;;
        xbps:sinit)    echo "sinit" ;;

        dnf:openrc)    echo "openrc" ;;
        dnf:runit)     echo "runit" ;;
        dnf:dinit)     echo "dinit" ;;
        dnf:s6)        echo "s6 s6-linux-init" ;;
        dnf:shepherd)  echo "shepherd" ;;
        dnf:finit)     echo "finit" ;;
        dnf:sinit)     echo "sinit" ;;

        zypper:openrc)   echo "openrc" ;;
        zypper:runit)    echo "runit" ;;
        zypper:dinit)    echo "dinit" ;;
        zypper:sysvinit) echo "sysvinit" ;;
        zypper:s6)       echo "s6 s6-linux-init" ;;
        zypper:shepherd) echo "shepherd" ;;
        zypper:finit)    echo "finit" ;;

        emerge:openrc)   echo "sys-apps/openrc" ;;
        emerge:runit)    echo "sys-process/runit" ;;
        emerge:dinit)    echo "sys-apps/dinit" ;;
        emerge:sysvinit) echo "sys-apps/sysvinit" ;;
        emerge:s6)       echo "sys-apps/s6 sys-apps/s6-rc sys-apps/s6-linux-init" ;;
        emerge:shepherd) echo "sys-apps/shepherd" ;;
        emerge:finit)    echo "sys-apps/finit" ;;
        emerge:sinit)    echo "sys-apps/sinit" ;;

        *) echo "" ;;
    esac
}

install_packages() {
    packages=$(pkg_names_for_init "$CHOSEN")
    [ -n "$PKG_INSTALL" ] || return 1
    [ -n "$packages" ] || return 1

    log "Пробуем установить через пакеты: $packages"
    if [ -n "$PKG_UPDATE" ]; then
        sh -c "$PKG_UPDATE" || return 1
    fi
    sh -c "$PKG_INSTALL $packages" || return 1
}

# ==========================================
# 4. Сборка из исходников для простых случаев
# ==========================================
install_build_tools() {
    command -v git >/dev/null 2>&1 && command -v make >/dev/null 2>&1 && return 0

    warn "Нужны git/make/компилятор. Пытаемся установить инструменты сборки."
    case "$PKG_MANAGER" in
        apt)    sh -c "$PKG_UPDATE" || true; sh -c "$PKG_INSTALL git build-essential" || true ;;
        dnf)    sh -c "$PKG_INSTALL git gcc make" || true ;;
        pacman) sh -c "$PKG_INSTALL git base-devel" || true ;;
        apk)    sh -c "$PKG_INSTALL git build-base" || true ;;
        xbps)   sh -c "$PKG_INSTALL git base-devel" || true ;;
        zypper) sh -c "$PKG_INSTALL git gcc make" || true ;;
        emerge) sh -c "$PKG_INSTALL dev-vcs/git sys-devel/gcc sys-devel/make" || true ;;
    esac

    command -v git >/dev/null 2>&1 && command -v make >/dev/null 2>&1
}

compile_from_source() {
    source_supported "$CHOSEN" || return 1
    install_build_tools || return 1

    TMPDIR=$(mktemp -d)
    log "Временный каталог сборки: $TMPDIR"

    oldpwd=$(pwd)
    cd "$TMPDIR" || return 1
    SUCCESS=0

    case "$CHOSEN" in
        dinit)
            log "Клонируем dinit..."
            git clone --depth 1 https://github.com/dinitdev/dinit.git
            cd dinit
            log "Компилируем dinit..."
            if make -j"$(nproc 2>/dev/null || echo 2)" && make install; then
                SUCCESS=1
            fi
            ;;
        runit)
            log "Клонируем runit..."
            git clone --depth 1 https://github.com/void-linux/runit.git
            cd runit
            log "Компилируем runit..."
            if make; then
                mkdir -p /usr/local/sbin
                copied=0
                for bin in runit runit-init chpst runsv runsvchdir runsvdir sv svlogd; do
                    src=""
                    if [ -f "$bin" ]; then
                        src="$bin"
                    else
                        src=$(find . -type f -name "$bin" -perm -111 2>/dev/null | sed -n '1p')
                    fi
                    if [ -n "$src" ] && [ -f "$src" ]; then
                        cp -f "$src" /usr/local/sbin/"$bin"
                        chmod 755 /usr/local/sbin/"$bin"
                        copied=$((copied + 1))
                    fi
                done
                [ "$copied" -gt 0 ] && SUCCESS=1
            fi
            ;;
        sinit)
            log "Клонируем sinit..."
            git clone --depth 1 https://git.suckless.org/sinit
            cd sinit
            log "Компилируем sinit..."
            if make; then
                mkdir -p /usr/local/sbin
                cp -f sinit /usr/local/sbin/sinit
                chmod 755 /usr/local/sbin/sinit
                SUCCESS=1
            fi
            ;;
    esac

    cd "$oldpwd" || cd /
    rm -rf "$TMPDIR" 2>/dev/null || true

    [ "$SUCCESS" = "1" ]
}

# ==========================================
# 5. Проверка результата
# ==========================================
is_systemd_symlink() {
    path=$1
    if command -v readlink >/dev/null 2>&1; then
        target=$(readlink -f "$path" 2>/dev/null || readlink "$path" 2>/dev/null || true)
        case "$target" in
            *systemd*) return 0 ;;
        esac
    fi
    return 1
}

find_init_path() {
    case "$1" in
        openrc)
            paths="/sbin/openrc-init /usr/sbin/openrc-init /usr/bin/openrc-init"
            ;;
        runit)
            paths="/sbin/runit-init /usr/sbin/runit-init /usr/bin/runit-init /usr/local/sbin/runit-init /lib/runit/runit-init /sbin/runit /usr/sbin/runit /usr/bin/runit /usr/local/sbin/runit"
            ;;
        dinit)
            paths="/sbin/dinit /usr/sbin/dinit /usr/bin/dinit /usr/local/sbin/dinit /usr/local/bin/dinit"
            ;;
        sysvinit)
            for p in /sbin/init /usr/sbin/init; do
                [ -x "$p" ] || continue
                is_systemd_symlink "$p" && continue
                [ -f /etc/inittab ] || continue
                echo "$p"
                return 0
            done
            return 1
            ;;
        s6)
            paths="/etc/s6-linux-init/current/bin/init /sbin/s6-linux-init /usr/sbin/s6-linux-init /usr/local/sbin/s6-linux-init"
            ;;
        shepherd)
            paths="/usr/bin/shepherd /bin/shepherd /usr/sbin/shepherd /usr/local/bin/shepherd"
            ;;
        finit)
            paths="/sbin/finit /usr/sbin/finit /usr/local/sbin/finit"
            ;;
        sinit)
            paths="/sbin/sinit /usr/sbin/sinit /usr/local/sbin/sinit"
            ;;
        epoch)
            paths="/sbin/epoch /usr/sbin/epoch /usr/local/sbin/epoch"
            ;;
        *)
            paths=""
            ;;
    esac

    for p in $paths; do
        if [ -x "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

post_install_notes() {
    case "$CHOSEN" in
        sysvinit)
            warn "SysVinit требует корректный /etc/inittab и набор rc-скриптов."
            warn "На systemd-дистрибутивах установка sysvinit-core может заменить /sbin/init."
            ;;
        s6)
            warn "Для s6 обычно нужно сгенерировать дерево s6-linux-init."
            warn "init-selector ищет, например: /etc/s6-linux-init/current/bin/init"
            ;;
        shepherd)
            warn "GNU Shepherd требует собственную конфигурацию сервисов. На обычных дистрибутивах она часто отсутствует."
            ;;
        finit)
            warn "Finit требует настроенный /etc/finit.conf."
            ;;
        sinit)
            warn "sinit крайне минимален: shutdown/reboot/getty/сервисы нужно организовать отдельно."
            ;;
        openrc)
            warn "OpenRC требует настроенные runlevel'ы и getty/network-сервисы."
            ;;
        runit)
            warn "runit требует stage-скрипты и каталог сервисов для полноценной загрузки."
            ;;
        dinit)
            warn "dinit требует каталог описаний сервисов и boot service."
            ;;
    esac
}

printf "Продолжить установку %b%s%b? [y/N]: " "$BOLD" "$CHOSEN" "$NC"
read -r confirm
case "$confirm" in
    y|Y|yes|YES) ;;
    *) log "Отмена установки."; exit 0 ;;
esac

echo
INSTALL_SUCCESS=0

if install_packages; then
    INSTALL_SUCCESS=1
else
    warn "Пакетная установка не удалась или пакет не описан для этого менеджера."
    if source_supported "$CHOSEN"; then
        warn "Пробуем собрать $CHOSEN из исходников..."
        if compile_from_source; then
            INSTALL_SUCCESS=1
        fi
    else
        warn "Автоматическая сборка $CHOSEN из исходников не реализована: слишком много distro-specific настроек."
    fi
fi

FOUND_PATH=$(find_init_path "$CHOSEN" 2>/dev/null || true)

if [ "$INSTALL_SUCCESS" != "1" ] || [ -z "$FOUND_PATH" ]; then
    error "Установка $CHOSEN не завершена до рабочего состояния для init-selector."
    if [ -z "$FOUND_PATH" ]; then
        error "Не найден ожидаемый исполняемый PID1-бинарник для $CHOSEN."
    fi
    post_install_notes
    exit 1
fi

# ==========================================
# Финал
# ==========================================
echo
log "Установка ${BOLD}$CHOSEN${NC} завершена успешно."
log "Найден путь для init-selector: $FOUND_PATH"
post_install_notes

echo
cat << EOF
${CYAN}=== Следующие шаги ===${NC}

1. Обновите конфигурацию init-selector и initramfs:
   ${YELLOW}sudo ./install.sh${NC}

2. Проверьте, что в /etc/init-selector/config появилась строка:
   ${YELLOW}$CHOSEN $FOUND_PATH${NC}

3. Перезагрузитесь и выберите $CHOSEN в меню,
   либо добавьте параметр ядра:
   ${YELLOW}initsel=$CHOSEN${NC}

${RED}ВНИМАНИЕ:${NC}
Новая init-система почти всегда требует дополнительной настройки
(getty, сеть, shutdown/reboot, runlevels/service directories и т.д.).
EOF

echo
log "Готово."
