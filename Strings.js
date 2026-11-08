// UI strings. Omarchy's own catalogs only cover first-party plugins, so this
// plugin carries its own and follows the shell language (I18n.language),
// falling back to English per string.

var catalogs = {
  en: {
    title: "VPN",
    on: "Connected",
    off: "Off",
    turningOn: "Connecting…",
    turningOff: "Turning off…",
    notRunning: "mihomo is not running",
    notRunningHelp: "Start the mihomo service to connect.",
    notRunningDevHelp: "No mihomo service is set up. Run install.sh, or scripts/dev-run.sh for a test run.",
    startService: "Start mihomo",
    noController: "No controller config",
    noControllerHelp: "Run install.sh, or write url and secret to %1",
    unauthorized: "The controller rejected the secret",
    missingGroups: "The config has no VPN group",
    auto: "Auto",
    routing: "Routing",
    routingDirect: "RU direct",
    routingVpn: "All via VPN",
    routingDirectHint: "Russian sites go direct, the rest through the VPN",
    routingVpnHint: "Everything except the local network goes through the VPN",
    servers: "Servers",
    noServers: "The subscription has no servers yet",
    testDelays: "Test latency",
    testing: "Testing…",
    updateSubscription: "Update subscription",
    updated: "Subscription updated",
    turnOn: "Turn VPN on",
    turnOff: "Turn VPN off",
    failed: "Request failed: %1",
    tunFailed: "Could not switch the tunnel. Is mihomo running as the system service?",
    timeout: "timeout",
    ms: "%1 ms"
  },
  ru: {
    title: "VPN",
    on: "Подключено",
    off: "Выключено",
    turningOn: "Подключение…",
    turningOff: "Выключение…",
    notRunning: "mihomo не запущен",
    notRunningHelp: "Запусти сервис mihomo, чтобы подключиться.",
    notRunningDevHelp: "Сервис mihomo не настроен. Запусти install.sh или scripts/dev-run.sh для теста.",
    startService: "Запустить mihomo",
    noController: "Нет настроек контроллера",
    noControllerHelp: "Запусти install.sh или впиши url и secret в %1",
    unauthorized: "Контроллер не принял secret",
    missingGroups: "В конфиге нет группы VPN",
    auto: "Авто",
    routing: "Маршрутизация",
    routingDirect: "RU напрямую",
    routingVpn: "Всё через VPN",
    routingDirectHint: "Российские сайты напрямую, остальное через VPN",
    routingVpnHint: "Всё, кроме локальной сети, через VPN",
    servers: "Серверы",
    noServers: "В подписке пока нет серверов",
    testDelays: "Проверить пинг",
    testing: "Проверяю…",
    updateSubscription: "Обновить подписку",
    updated: "Подписка обновлена",
    turnOn: "Включить VPN",
    turnOff: "Выключить VPN",
    failed: "Ошибка запроса: %1",
    tunFailed: "Не удалось переключить туннель. mihomo запущен как системный сервис?",
    timeout: "таймаут",
    ms: "%1 мс"
  }
}

function lookup(language, key) {
  var code = String(language || "en").split("-")[0]
  var table = catalogs[code] || catalogs.en
  var value = table[key]
  if (value === undefined) value = catalogs.en[key]
  return value === undefined ? key : value
}

// t(language, key, arg1, arg2...) with %1, %2 holes.
function t(language, key) {
  var text = String(lookup(language, key))
  for (var i = 2; i < arguments.length; i++) {
    text = text.split("%" + (i - 1)).join(String(arguments[i]))
  }
  return text
}
