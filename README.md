# Octavich Dotfiles 🌌

## 🚀 Plug and Play Installation

Run this single command to automatically download, install dependencies, and configure your entire system:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/octavich/.dotfile/main/install.sh)"
```

---

| Environment   | Name   |
|---------------|--------|
| DE            | niri  ⭐ |
| Bar           | waybar |
| Launcher      | vicinae + fuzzel |
| Login Manager | tty    |
| Shell         | fish + starship  |

## 📖 Краткий гайд (Quick Start)

### 🎨 Смена обоев и цветов системы
Обои управляются утилитой `swww`, а цветовая схема генерируется автоматически через `matugen`. Для удобства уже настроен алиас `sww` в вашем терминале (fish). 

Чтобы поменять обои и перекрасить всю систему в их цвета (Kitty, Waybar, GTK), просто введите в терминале:
```bash
sww ~/Pictures/ваша_картинка.jpg
```

### ⌨️ Горячие клавиши (Niri)
- `Mod + Enter` — Открыть терминал (Kitty)
- `Mod + D` — Открыть меню приложений (Vicinae)
- `Mod + V` — История буфера обмена
- `Mod + X` — Обзор всех открытых окон (Overview)
- `Mod + Q` — Закрыть активное окно
- `Mod + P` — Меню выключения
- `Mod + W` — Скрипт выбора окон/экранов
- `Mod + Shift + C` — Взять цвет с экрана (Hyprpicker)
