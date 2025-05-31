# Шаблон Odin Raylib + ImGui

Стартовый шаблон для проектов на [Odin](https://odin-lang.org/), с уже настроенными [Raylib](https://www.raylib.com/) и [Dear ImGui](https://github.com/ocornut/imgui) биндингами.

Доступные языки:
- [English/EN](README.md)
- [Русский/RU](README.ru.md)

## Особенности

- Подключён `imgui` + `imgui_impl_raylib`
- Структура проекта минимальна
- Готов к сборке без дополнительной настройки

## Требования

- [Odin](https://odin-lang.org/docs/install) (Все остальные пакеты включены)

## Сборка

На Windows:
```cpp
./build.bat
```
На Linux:
```bash
./build.sh
```

## Использованные источники

- [imgui_impl_raylib](https://gist.github.com/lucaspoffo/a0d4192acd74d718e433ea0bafe17bc4) (был немного изменён для корректной работы)
- [odin-imgui](https://gitlab.com/L-4/odin-imgui)
