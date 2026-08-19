import Config

config :logger, level: :info

# 12111 is stripe-mock's default port, so an existing stripe-mock service
# definition can be repointed at PaperTiger without changing the port anywhere
# else. Override at runtime with PAPER_TIGER_PORT or PORT.
config :paper_tiger, port: 12_111

# The standalone release has no host application to run seeding for it, so the
# bootstrap worker — test tokens, data_source, init_data, configured webhooks —
# is its only chance to load any of those. Library consumers opt in from their
# own config; the release opts in here.
config :paper_tiger, enable_bootstrap: true
