#!/bin/bash
# Marsik-комментарий: выбираем LTS-ядро как артефакт стабильности

# Список известных LTS-ядер
declare -A lts_kernels=(
  ["6.6"]="до декабря 2025"
  ["6.1"]="до декабря 2026"
  ["5.15"]="до октября 2026"
  ["5.10"]="до декабря 2026"
  ["5.4"]="до декабря 2025"
)

# Список зеркал
mirrors=(
  "https://repo-default.voidlinux.org/current"
  "https://repo-default.voidlinux.org/current/nonfree"
  "https://repo-de.voidlinux.org/current"
  "https://repo-de.voidlinux.org/current/nonfree"
  "https://repo-fr.voidlinux.org/current"
  "https://repo-fr.voidlinux.org/current/nonfree"
)

# Временный файл для результатов
tmpfile=$(mktemp)

echo "🔍 Ищу доступные LTS-ядра по всем зеркалам..."

for mirror in "${mirrors[@]}"; do
  echo "🌐 Проверяю зеркало: $mirror"
  for ver in "${!lts_kernels[@]}"; do
    if xbps-query -Rs "linux$ver" --repository="$mirror" 2>/dev/null | grep -q "linux$ver-[0-9]"; then
      echo "$ver" >> "$tmpfile"
    fi
  done
done

# Удаляем дубликаты и сортируем
available=($(sort -Vu "$tmpfile"))
rm "$tmpfile"

if [ ${#available[@]} -eq 0 ]; then
  echo "❌ Нет доступных LTS-ядер. Проверь зеркало или интернет."
  exit 1
fi

echo "📜 Доступные LTS-ядра:"
for i in "${!available[@]}"; do
  ver="${available[$i]}"
  echo "$((i+1))) linux$ver — поддержка ${lts_kernels[$ver]}"
done

echo -n "Выбери номер ядра: "
read choice

ver="${available[$((choice-1))]}"
if [ -z "$ver" ]; then
  echo "❌ Неверный выбор."
  exit 1
fi

echo "⚙️ Устанавливаю linux$ver..."
if sudo xbps-install -y "linux$ver"; then
  echo "✅ Установлено linux$ver"
  echo "🔄 Обновляю загрузчик..."
  sudo xbps-reconfigure -f grub
  echo "$(date): Установлено linux$ver" >> ~/kernel-install.log
else
  echo "❌ Ошибка установки! Проверь зеркало или зависимости."
fi

