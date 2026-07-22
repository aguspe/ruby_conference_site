require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Backs the RSVP form's `rate_limit` (see RsvpsController). Per-process, so
  # this is only correct on a single instance, which is what this service is.
  # If the service is ever scaled to two instances, move to Redis.
  config.cache_store = :memory_store

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # RsvpMailer is delivered inline with `deliver_now` (see RsvpsController),
  # not `deliver_later`, so Active Job's queue adapter is irrelevant to mail
  # durability here: at ~40 seats, the default in-process AsyncAdapter's
  # non-persistence (anything queued is lost on every deploy restart) is a
  # real risk for a job queue, but not for something that never gets queued.
  # config.active_job.queue_adapter = :resque

  # `true` so a transport failure raises out of `deliver_now` instead of being
  # swallowed inside ActionMailer. RsvpsController rescues that raise itself,
  # logs it, and continues — the reservation is already saved by the time
  # mail is attempted, so a mail failure still can never fail the request.
  # Raising here (rather than swallowing) is what makes the failure visible
  # in the logs instead of silently disappearing.
  config.action_mailer.raise_delivery_errors = true

  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.smtp_settings = {
    address:              "smtp.resend.com",
    port:                 587,
    user_name:            "resend",
    password:             ENV["RESEND_API_KEY"],
    authentication:       :plain,
    enable_starttls_auto: true
  }

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "hyggerb.dk"), protocol: "https" }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
