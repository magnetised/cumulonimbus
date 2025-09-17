import Config

config :logger,
  level: :info,
  compile_time_purge_matching: [
    [application: :electric, level_lower_than: :error]
  ]

config :logger,
  level: :info,
  compile_time_purge_matching: [
    [application: :electric, level_lower_than: :error]
  ]
