# ffpp — Минималистичный VLESS клиент для iOS (17+)

Минималистичный, быстрый и энергоэффективный VLESS-клиент для iOS с нативным туннелем (`PacketTunnelProvider`), полноценной эмуляцией клиента **Happ** (обход проверки `User-Agent` и привязка постоянного `X-Hwid`) и тройной системой защиты сохранности подписок.

---

## Ключевые возможности

* **Нативный VLESS + Reality:** поддержка современных протоколов маскировки (Reality, uTLS Chrome fingerprinting, Vision, gRPC, WebSocket).
* **Полная поддержка подписок Happ:**
  * Запросы подписки отправляются с официальными заголовками:
    * `User-Agent: Happ/3.13.0 (...)`
    * `X-Hwid: <постоянный UUID>`
    * `X-Device-Os: iOS`
    * `X-Device-Model: iPhone...`
  * Поддерживаются схемы `happ://`, base64-списки и стандартные `vless://`.
* **Постоянный HWID без слета:**
  * Уникальный идентификатор устройства сохраняется в защищенное хранилище **iOS Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
  * Он не меняется и не сбрасывается при закрытии, очистке памяти или переустановке приложения.
  * Доступен просмотр, копирование и ручной ввод HWID в меню Настроек.
* **Тройная защита подписок от потери:**
  * Атомарная запись в изолированную директорию приложения (`.atomic`).
  * Дублирование в App Group контейнер и резервный кэш `UserDefaults`.
  * Функция ручного экспорта и импорта полного JSON-бэкапа (в «Файлы» или мессенджеры).
* **Автоматическая сборка в GitHub Actions:**
  * Сборка чистого `.ipa` на macOS-раннере без необходимости держать локальный Mac.

---

## Архитектура проекта

```
ffpp/
├── App/                         # Главное iOS SwiftUI приложение
│   ├── ViewModels/              # AppViewModel, VPNManager (NETunnelProviderManager)
│   ├── Views/                   # DashboardView, ServerListView, SubscriptionView, SettingsView
│   ├── Info.plist
│   └── ffpp.entitlements
├── Tunnel/                      # Системное расширение VPN (Network Extension)
│   ├── PacketTunnelProvider.swift
│   ├── Info.plist
│   └── ffppTunnel.entitlements  # packet-tunnel-provider entitlement
├── Shared/                      # Общие модули приложения и расширения
│   ├── Models/                  # ServerConfig, Subscription, AppSettings
│   └── Services/                # KeychainHelper, StorageManager, HappSubscriptionService, SingBoxConfigBuilder
├── .github/workflows/build.yml  # GitHub Actions CI для сборки .ipa
└── project.yml                  # Спецификация XcodeGen для сборки
```

---

## Установка и подписание через GBox (покупной сертификат)

1. Зайдите в репозиторий в раздел **Actions** на GitHub и скачайте артефакт `ffpp-unsigned-ipa` (или возьмите файл из **Releases**).
2. Распакуйте архив, чтобы получить `ffpp-unsigned.ipa`.
3. Откройте **GBox** на вашем iPhone.
4. Импортируйте ваш покупной сертификат разработчика (`.p12`) и файл профиля (`.mobileprovision`).
5. Добавьте `ffpp-unsigned.ipa` в GBox.
6. **Критически важный шаг перед подписанием в GBox:**
   * Откройте меню подписи приложения в GBox.
   * Убедитесь, что включена опция **«Подписывать расширения / PlugIns» (Sign Extensions / PlugIns)**.
   * *(Это необходимо, чтобы расширение `ffppTunnel.appex` было подписано тем же сертификатом, иначе туннель не запустится)*.
7. Нажмите «Подписать» и установите приложение.
8. При первом нажатии на кнопку питания в приложении подтвердите системный запрос iOS на добавление конфигурации VPN.

---

## Сборка через GitHub Actions вручную

1. Перейдите во вкладку **Actions** в репозитории `ffpp`.
2. Выберите workflow **«Build iOS IPA»**.
3. Нажмите кнопку **Run workflow** -> выберите ветку `main` -> нажмите **Run workflow**.
4. Примерно через 2–3 минуты готовый `.ipa` будет доступен для скачивания в блоке **Artifacts**.
