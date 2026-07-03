#!/bin/sh

# ==============================================================================
# 
# этот ГОВНОскрипт ОТ 30.11.2025  для создания пользователя, ограниченного только SSH-туннелированием
# с возможностью выбора имени и пароля.
# ==============================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

DEFAULT_USER="user-port"
DEFAULT_PASS_LEN=8
CONFIG_DIR="/etc/tunnel_users"
USER_LIST_FILE="$CONFIG_DIR/users.list"

# Функция для получения IP сервера
get_server_ip() {
    # Пробуем разные методы получения IP
    local ip=""
    
    # 1. Через hostname -I (наиболее надежный способ)
    if command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    # 2. Через ip route (для Linux)
    if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    fi
    
    # 3. Через ifconfig (устаревший способ, но для совместимости)
    if [ -z "$ip" ] && command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)
    fi
    
    # 4. Если все методы не сработали, используем localhost
    if [ -z "$ip" ]; then
        ip="localhost"
    fi
    
    echo "$ip"
}

# Создаем директорию для хранения данных о пользователях
create_config_dir() {
    if [ ! -d "$CONFIG_DIR" ]; then
        sudo mkdir -p "$CONFIG_DIR"
        sudo chmod 755 "$CONFIG_DIR"
    fi
    if [ ! -f "$USER_LIST_FILE" ]; then
        sudo touch "$USER_LIST_FILE"
        sudo chmod 644 "$USER_LIST_FILE"
    fi
}

# --- Функция для генерации случайного пароля ---
generate_random_password() {
    # Генерируем случайный пароль только из букв и цифр
    local length=$1
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

# --- Функция добавления пользователя в список ---
add_user_to_list() {
    local username="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$username|$timestamp" | sudo tee -a "$USER_LIST_FILE" > /dev/null
}

# --- Функция удаления пользователя из списка ---
remove_user_from_list() {
    local username="$1"
    sudo grep -v "^$username|" "$USER_LIST_FILE" | sudo tee "$USER_LIST_FILE.tmp" > /dev/null
    sudo mv "$USER_LIST_FILE.tmp" "$USER_LIST_FILE"
}

# --- Функция показа созданных пользователей ---
show_created_users() {
    echo ""
    echo "### Созданные пользователи для туннелирования ###"
    echo ""
    
    if [ ! -s "$USER_LIST_FILE" ]; then
        echo "Нет созданных пользователей."
        return
    fi
    
    echo "Имя пользователя        | Дата создания"
    echo "------------------------|----------------------"
    while IFS='|' read -r username date_created; do
        # Проверяем, существует ли пользователь в системе
        if id "$username" >/dev/null 2>&1; then
            status="✅ АКТИВЕН"
        else
            status="❌ УДАЛЕН"
        fi
        printf "%-23s | %s %s\n" "$username" "$date_created" "$status"
    done < "$USER_LIST_FILE"
    echo ""
}

# --- Функция удаления пользователя ---
delete_user() {
    show_created_users
    
    if [ ! -s "$USER_LIST_FILE" ]; then
        echo "Нет пользователей для удаления."
        return
    fi
    
    echo ""
    printf "Введите имя пользователя для удаления: "
    read USER_TO_DELETE
    
    if [ -z "$USER_TO_DELETE" ]; then
        echo "Ошибка: Имя пользователя не может быть пустым."
        return
    fi
    
    # Проверяем, есть ли пользователь в списке
    if ! sudo grep -q "^$USER_TO_DELETE|" "$USER_LIST_FILE"; then
        echo "Ошибка: Пользователь '$USER_TO_DELETE' не найден в списке созданных пользователей."
        return
    fi
    
    # Удаляем пользователя из системы
    if id "$USER_TO_DELETE" >/dev/null 2>&1; then
        echo "Удаляем пользователя '$USER_TO_DELETE' из системы..."
        sudo deluser --remove-home "$USER_TO_DELETE" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "✅ Пользователь '$USER_TO_DELETE' удален из системы."
        else
            echo "❌ Ошибка при удалении пользователя '$USER_TO_DELETE'."
        fi
    else
        echo "ℹ️  Пользователь '$USER_TO_DELETE' уже удален из системы."
    fi
    
    # Удаляем пользователя из списка
    remove_user_from_list "$USER_TO_DELETE"
    echo "✅ Пользователь '$USER_TO_DELETE' удален из списка."
}

# --- Функция смены пароля пользователя ---
change_password() {
    show_created_users
    
    if [ ! -s "$USER_LIST_FILE" ]; then
        echo "Нет пользователей для смены пароля."
        return
    fi
    
    echo ""
    printf "Введите имя пользователя для смены пароля: "
    read USER_TO_CHANGE
    
    if [ -z "$USER_TO_CHANGE" ]; then
        echo "Ошибка: Имя пользователя не может быть пустым."
        return
    fi
    
    # Проверяем, есть ли пользователь в списке
    if ! sudo grep -q "^$USER_TO_CHANGE|" "$USER_LIST_FILE"; then
        echo "Ошибка: Пользователь '$USER_TO_CHANGE' не найден в списке созданных пользователей."
        return
    fi
    
    # Проверяем, существует ли пользователь в системе
    if ! id "$USER_TO_CHANGE" >/dev/null 2>&1; then
        echo "Ошибка: Пользователь '$USER_TO_CHANGE' не существует в системе."
        return
    fi
    
    echo ""
    echo "Смена пароля для пользователя: $USER_TO_CHANGE"
    echo ""
    echo "Выберите опцию пароля:"
    echo "   1) Сгенерировать случайный пароль ($DEFAULT_PASS_LEN символов)"
    echo "   2) Ввести пароль вручную"
    printf "Введите 1 или 2 (по умолчанию: 1): "
    read PASS_CHOICE

    NEW_PASSWORD=""

    if [ "$PASS_CHOICE" = "2" ]; then
        echo ""
        echo "--- Введите новый пароль ---"
        printf "Новый пароль: "
        stty -echo
        read MANUAL_PASSWORD
        stty echo
        echo "" # Новая строка
        NEW_PASSWORD="$MANUAL_PASSWORD"
        
        if [ -z "$NEW_PASSWORD" ]; then
            echo "Ошибка: Пароль не может быть пустым."
            return 1
        fi
    else
        # Случайный пароль по умолчанию
        NEW_PASSWORD=$(generate_random_password "$DEFAULT_PASS_LEN")
        echo "   -> Сгенерирован случайный пароль: ${GREEN}${BOLD}$NEW_PASSWORD${NC}"
        echo "   ${RED}${BOLD}!!! ЗАПИШИТЕ ЭТОТ ПАРОЛЬ !!!${NC}"
    fi

    # Меняем пароль пользователя
    echo ""
    echo "Меняем пароль для пользователя '$USER_TO_CHANGE'..."
    
    # Используем chpasswd для надежной установки пароля
    echo "$USER_TO_CHANGE:$NEW_PASSWORD" | sudo chpasswd
    
    if [ $? -eq 0 ]; then
        SERVER_IP=$(get_server_ip)
        echo "✅ Пароль для пользователя '$USER_TO_CHANGE' успешно изменен."
        echo ""
        echo "Новые данные:"
        echo "   - Имя пользователя: ${CYAN}${BOLD}$USER_TO_CHANGE${NC}"
        echo "   - Новый пароль: ${GREEN}${BOLD}$NEW_PASSWORD${NC}"
        echo ""
        echo "Команда для проброса порта:"
        echo "ssh -N -L 9999:ХОСТ:ПОРТ ${CYAN}${BOLD}$USER_TO_CHANGE${NC}@${SERVER_IP}"
    else
        echo "❌ Ошибка при смене пароля для пользователя '$USER_TO_CHANGE'."
    fi
}

# --- Функция создания пользователя ---
create_user() {
    echo ""
    echo "### Настройка пользователя для туннелирования ###"
    echo ""
    echo "1. Имя пользователя"
    printf "Введите имя пользователя (по умолчанию: %s): " "$DEFAULT_USER"
    read CUSTOM_USER

    if [ -z "$CUSTOM_USER" ]; then
        TUNNEL_USER="$DEFAULT_USER"
    else
        TUNNEL_USER="$CUSTOM_USER"
    fi

    # Проверка, что имя пользователя корректно
    if ! echo "$TUNNEL_USER" | grep -q '^[a-z_][a-z0-9_-]\{0,30\}$'; then
        echo "Ошибка: Имя пользователя содержит недопустимые символы или слишком длинное."
        return 1
    fi

    echo "   -> Будет использовано имя: ${CYAN}${BOLD}$TUNNEL_USER${NC}"

    # --- Запрос пароля ---
    echo ""
    echo "2. Пароль"
    echo "Выберите опцию пароля:"
    echo "   1) Сгенерировать случайный пароль ($DEFAULT_PASS_LEN символов)"
    echo "   2) Ввести пароль вручную"
    printf "Введите 1 или 2 (по умолчанию: 1): "
    read PASS_CHOICE

    FINAL_PASSWORD=""

    if [ "$PASS_CHOICE" = "2" ]; then
        echo ""
        echo "--- Введите новый пароль ---"
        printf "Пароль: "
        stty -echo
        read MANUAL_PASSWORD
        stty echo
        echo "" # Новая строка
        FINAL_PASSWORD="$MANUAL_PASSWORD"
        
        if [ -z "$FINAL_PASSWORD" ]; then
            echo "Ошибка: Пароль не может быть пустым."
            return 1
        fi
    else
        # Случайный пароль по умолчанию
        FINAL_PASSWORD=$(generate_random_password "$DEFAULT_PASS_LEN")
        echo "   -> Сгенерирован случайный пароль: ${GREEN}${BOLD}$FINAL_PASSWORD${NC}"
        echo "   ${RED}${BOLD}!!! ЗАПИШИТЕ ЭТОТ ПАРОЛЬ !!!${NC}"
    fi

    # --- Создание пользователя ---
    echo ""
    echo "3. Создание пользователя '$TUNNEL_USER'..."

    # Проверка и удаление старого пользователя (для чистой установки)
    if id "$TUNNEL_USER" >/dev/null 2>&1; then
        echo "   Пользователь '$TUNNEL_USER' уже существует. Удаляем его для чистой установки."
        sudo deluser --remove-home "$TUNNEL_USER" >/dev/null 2>&1
        # Даем системе время на удаление
        sleep 2
    fi

    # Создаем пользователя без пароля сначала
    sudo useradd -m -s /sbin/nologin "$TUNNEL_USER"

    if [ $? -ne 0 ]; then
        echo "❌ Ошибка: Не удалось создать пользователя."
        return 1
    fi

    # Устанавливаем пароль используя chpasswd (более надежный метод)
    echo "$TUNNEL_USER:$FINAL_PASSWORD" | sudo chpasswd

    if [ $? -ne 0 ]; then
        echo "❌ Ошибка: Не удалось установить пароль для пользователя."
        # Удаляем пользователя если не удалось установить пароль
        sudo deluser --remove-home "$TUNNEL_USER" >/dev/null 2>&1
        return 1
    fi

    # Добавляем пользователя в список
    add_user_to_list "$TUNNEL_USER"

    # Получаем IP сервера
    SERVER_IP=$(get_server_ip)

    echo ""
    echo "### ✅ Пользователь '$TUNNEL_USER' успешно создан. ###"
    echo "   - Имя пользователя: ${CYAN}${BOLD}$TUNNEL_USER${NC}"
    echo "   - Пароль: ${GREEN}${BOLD}$FINAL_PASSWORD${NC}"
    echo "   - Оболочка: /sbin/nologin (интерактивный вход запрещен)"
    echo "   - IP сервера: ${YELLOW}${BOLD}$SERVER_IP${NC}"
    echo "   - ✅ ГОТОВ К ТУННЕЛИРОВАНИЮ"
    echo ""
    echo "Команда для проброса порта:"
    echo "ssh -N -L 9999:ХОСТ:ПОРТ ${CYAN}${BOLD}$TUNNEL_USER${NC}@${SERVER_IP}"
    echo ""
    echo "Пример для проброса локального порта 3306 (MySQL):"
    echo "ssh -N -L 9999:localhost:3306 ${CYAN}${BOLD}$TUNNEL_USER${NC}@${SERVER_IP}"
    echo ""
    echo "⚠️  Для тестирования подключения выполните:"
    echo "ssh ${CYAN}${BOLD}$TUNNEL_USER${NC}@${SERVER_IP} echo 'Подключение успешно!'"
}

# --- Главное меню ---
main_menu() {
    while true; do
        echo ""
        echo "========================================="
        echo "       Передай Потапу привеД !!!"
        echo "    Меню управления пользователями"
        echo "========================================="
        echo "1 - Создание пользователя"
        echo "2 - Удалить пользователя"
        echo "3 - Поменять пароль для пользователя"
        echo "4 - Показать созданных пользователей"
        echo "5 - Выход"
        echo ""
        printf "Выберите действие (1-5): "
        read choice
        
        case "$choice" in
            1)
                create_user
                ;;
            2)
                delete_user
                ;;
            3)
                change_password
                ;;
            4)
                show_created_users
                ;;
            5)
                echo "Выход..."
                exit 0
                ;;
            *)
                echo "Ошибка: Неверный выбор. Попробуйте снова."
                ;;
        esac
        
        echo ""
        printf "Нажмите Enter для продолжения..."
        read wait
    done
}

# ==============================================================================
# Основная программа
# ==============================================================================

create_config_dir
main_menu
