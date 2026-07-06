#!/bin/sh
#
# install-init.sh
# Помощник по установке альтернативных init-систем
# Для проекта init-selector
#
# Функции:
# - Определяет дистрибутив (Debian 13, Fedora, Arch и т.д.)
# - Показывает ТОЛЬКО те init-системы, которые можно установить
# - Если на дистрибутиве ничего нельзя поставить из пакетов — честно говорит
# - Пользователь выбирает цифрой (1 openrc, 2 runit, 3 dinit)
# - Устанавливает через пакетный менеджер или компилирует из исходников
#

set -e

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()   { printf "%b\n" "${GREEN}[+]${NC} $*"; }
warn()  { printf "%b\n" "${YELLOW}[!]${NC} $*"; }
error() { printf "%b\n" "${RED}[x]${NC} $*" >&2; }
info()  { printf "%b\n" "${CYAN}[i]${NC} $*"; }

# Проверка прав
if [ "$(id -u)" -ne 0 ]; then
    error "Запустите скрипт от имени root: sudo ./install-init.sh"
    exit 1
fi

echo
echo "${BOLD}=== Помощник установки init-систем ===${NC}"
echo "Проект: init-selector"
echo

# ==========================================
# 1. Определение дистрибутива
# ==========================================
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
        DISTRO_NAME="$NAME"
        DISTRO_VERSION="${VERSION_ID:-unknown}"
    else
        DISTRO_ID="unknown"
        DISTRO_NAME="Unknown Linux"
        DISTRO_VERSION="unknown"
    fi
}

detect_distro
log "Обнаружено: $DISTRO_NAME ($DISTRO_ID $DISTRO_VERSION)"
echo

# ==========================================
# 2. Определяем, какие init можно установить
# ==========================================
get_available_inits() {
    case "$DISTRO_ID" in
        # Debian-based
        debian|ubuntu|devuan|linuxmint|kali|pop|elementary)
            echo "openrc runit"
            ;;
        # Arch-based
        artix)
            echo "openrc runit dinit"
            ;;
        arch|manjaro|endeavouros|garuda)
            echo "openrc runit"
            ;;
        # Gentoo
        gentoo)
            echo "openrc runit dinit"
            ;;
        # Alpine
        alpine)
            echo "openrc"
            ;;
        # Void Linux
        void)
            echo "runit"
            ;;
        # openSUSE
        opensuse*|suse*)
            echo "openrc"
            ;;
        # Fedora/RHEL — почти ничего в официальных репах
        fedora|rhel|centos|rocky|almalinux|ol)
            echo ""
            ;;
        *)
            echo ""
            ;;
    esac
}

AVAILABLE_INITS=$(get_available_inits)

# ==========================================
# 3. Показываем меню пользователю
# ==========================================
echo "${BOLD}Доступные init-системы для вашего дистрибутива:${NC}"
echo

if [ -z "$AVAILABLE_INITS" ]; then
    echo "  На вашем дистрибутиве в официальных репозиториях"
    echo "  нет готовых пакетов альтернативных init-систем."
    echo
    warn "Можно установить только путём компиляции из исходников."
    echo
    echo "  1) openrc"
    echo "  2) runit"
    echo "  3) dinit"
    echo "  4) Отмена"
    echo
    printf "Выберите номер: "
    read -r choice

    case "$choice" in
        1) CHOSEN="openrc" ; NEED_COMPILE=1 ;;
        2) CHOSEN="runit"  ; NEED_COMPILE=1 ;;
        3) CHOSEN="dinit"  ; NEED_COMPILE=1 ;;
        *) log "Отмена."; exit 0 ;;
    esac
else
    i=1
    for init in $AVAILABLE_INITS; do
        case "$init" in
            openrc) desc="OpenRC — популярный, удобный, много сервисов" ;;
            runit)  desc="runit — минималистичный и очень быстрый" ;;
            dinit)  desc="dinit — современный, простой и надёжный" ;;
        esac
        echo "  $i) $init — $desc"
        eval "MENU_$i=$init"
        i=$((i + 1))
    done

    echo "  $i) Отмена"
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
    NEED_COMPILE=0
fi

echo
log "Вы выбрали: ${BOLD}$CHOSEN${NC}"
echo

# ==========================================
# 4. Установка
# ==========================================

# Определяем пакетный менеджер
detect_pkg() {
    if command -v apt-get >/dev/null 2>&1; then
        PKG_UPDATE="apt-get update"
        PKG_INSTALL="apt-get install -y"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_UPDATE="dnf makecache"
        PKG_INSTALL="dnf install -y"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_UPDATE="pacman -Sy"
        PKG_INSTALL="pacman -S --noconfirm"
    elif command -v apk >/dev/null 2>&1; then
        PKG_UPDATE="apk update"
        PKG_INSTALL="apk add"
    elif command -v xbps-install >/dev/null 2>&1; then
        PKG_UPDATE="xbps-install -S"
        PKG_INSTALL="xbps-install -y"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_UPDATE="zypper refresh"
        PKG_INSTALL="zypper install -y"
    elif command -v emerge >/dev/null 2>&1; then
        PKG_UPDATE="emerge --sync"
        PKG_INSTALL="emerge -q"
    else
        PKG_UPDATE=""
        PKG_INSTALL=""
    fi
}

detect_pkg

# Установка через пакеты
install_with_pkg() {
    case "$CHOSEN" in
        openrc)
            case "$DISTRO_ID" in
                debian|ubuntu|devuan|linuxmint|kali)
                    $PKG_UPDATE
                    $PKG_INSTALL openrc openrc-init
                    ;;
                arch|manjaro|endeavouros)
                    $PKG_UPDATE
                    $PKG_INSTALL openrc
                    ;;
                artix)
                    $PKG_UPDATE
                    $PKG_INSTALL openrc
                    ;;
                alpine)
                    $PKG_INSTALL openrc
                    ;;
                gentoo)
                    $PKG_INSTALL sys-apps/openrc
                    ;;
                opensuse*)
                    $PKG_UPDATE
                    $PKG_INSTALL openrc
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        runit)
            case "$DISTRO_ID" in
                debian|ubuntu|devuan)
                    $PKG_UPDATE
                    $PKG_INSTALL runit runit-init
                    ;;
                arch|manjaro)
                    $PKG_UPDATE
                    $PKG_INSTALL runit
                    ;;
                artix)
                    $PKG_UPDATE
                    $PKG_INSTALL runit
                    ;;
                void)
                    $PKG_INSTALL runit
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        dinit)
            case "$DISTRO_ID" in
                artix)
                    $PKG_UPDATE
                    $PKG_INSTALL dinit
                    ;;
                gentoo)
                    $PKG_INSTALL sys-apps/dinit
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
    esac
}

# Компиляция из исходников
compile_init() {
    log "Начинаем компиляцию $CHOSEN из исходников..."

    if ! command -v git >/dev/null 2>&1; then
        warn "Устанавливаем git и инструменты сборки..."
        case "$PKG_INSTALL" in
            *"apt-get"*) $PKG_INSTALL git build-essential ;;
            *"dnf"*)     $PKG_INSTALL git gcc make ;;
            *"pacman"*)  $PKG_INSTALL git base-devel ;;
            *"apk"*)     $PKG_INSTALL git build-base ;;
            *)           warn "Не удалось автоматически установить git" ;;
        esac
    fi

    TMPDIR=$(mktemp -d)
    cd "$TMPDIR" || die "Не могу создать временную папку"

    case "$CHOSEN" in
        dinit)
            log "Клонируем репозиторий dinit..."
            git clone --depth 1 https://github.com/dinitdev/dinit.git
            cd dinit
            log "Компилируем (может занять 1-3 минуты)..."
            make -j"$(nproc 2>/dev/null || echo 2)"
            make install
            ;;
        runit)
            log "Клонируем репозиторий runit..."
            git clone --depth 1 https://github.com/void-linux/runit.git
            cd runit
            make
            make install
            ;;
        openrc)
            error "Компиляция OpenRC из исходников очень сложная."
            error "Лучше используйте пакеты вашего дистрибутива."
            cd /
            rm -rf "$TMPDIR"
            return 1
            ;;
    esac

    cd /
    rm -rf "$TMPDIR"
    log "$CHOSEN успешно скомпилирован и установлен."
}

# === Запуск установки ===

printf "Продолжить установку ${BOLD}%s${NC}? [y/N]: " "$CHOSEN"
read -r confirm
case "$confirm" in
    y|Y) ;;
    *) log "Отмена установки."; exit 0 ;;
esac

echo

if [ "$NEED_COMPILE" = "1" ]; then
    compile_init || die "Не удалось скомпилировать $CHOSEN"
else
    if ! install_with_pkg 2>/dev/null; then
        warn "Не удалось установить через пакеты. Пробуем скомпилировать..."
        compile_init || die "Установка провалилась"
    fi
fi

# ==========================================
# Финал
# ==========================================
echo
log "Установка ${BOLD}$CHOSEN${NC} завершена успешно!"
echo

cat << EOF
${CYAN}=== Следующие шаги ===${NC}

1. Проверьте, что бинарник появился:
   ${YELLOW}ls -l /sbin/*init* /usr/bin/*init* /usr/local/sbin/*init* 2>/dev/null${NC}

2. Обновите конфигурацию init-selector:
   ${YELLOW}cd /путь/к/init-selector && sudo ./install.sh${NC}

3. Перезагрузитесь и в меню выберите $CHOSEN,
   или добавьте в параметры ядра:
   ${YELLOW}initsel=$CHOSEN${NC}

${RED}ВНИМАНИЕ:${NC}
Новая init-система почти всегда требует дополнительной настройки
(включение getty, сетевых служб и т.д.).

${YELLOW}Сначала обязательно протестируйте в виртуальной машине!${NC}
EOF

echo
log "Готово."