require "csv"

class Admin::RsvpsController < ApplicationController
  before_action :authenticate_organiser

  # Leading characters that spreadsheet applications (Excel, Google Sheets)
  # interpret as the start of a formula when a CSV cell is opened. Attendee
  # names and dietary notes come straight from an anonymous public form, so a
  # submission like `=cmd|'/c calc'!A1` would execute as a live formula for
  # whoever opens the export. Neutralised below by prefixing such cells with
  # a single quote, the standard CSV-injection mitigation.
  FORMULA_PREFIXES = [ "=", "+", "-", "@" ].freeze

  def index
    @rsvps = Rsvp.order(created_at: :asc)

    respond_to do |format|
      format.html
      format.csv do
        send_data to_csv(@rsvps),
          filename: "hyggerb-rsvps-#{Date.current.iso8601}.csv",
          type: "text/csv"
      end
    end
  end

  private

  def authenticate_organiser
    authenticate_or_request_with_http_basic("hygge.rb admin") do |user, password|
      expected_user     = ENV.fetch("ADMIN_USER", "")
      expected_password = ENV.fetch("ADMIN_PASSWORD", "")

      # Fail closed when unset, so a misconfigured deploy can't be walked into
      # with empty credentials.
      next false if expected_user.empty? || expected_password.empty?

      ActiveSupport::SecurityUtils.secure_compare(user, expected_user) &
        ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
    end
  end

  def to_csv(rsvps)
    CSV.generate(headers: true) do |csv|
      csv << %w[name email dietary waitlisted created_at]
      rsvps.each do |rsvp|
        csv << [
          csv_safe(rsvp.name),
          rsvp.email,
          csv_safe(rsvp.dietary),
          rsvp.waitlisted,
          rsvp.created_at.iso8601
        ]
      end
    end
  end

  # Prefixes a value with a single quote if it starts with a character a
  # spreadsheet would treat as a formula trigger. Leaves everything else, and
  # blank/nil fields, untouched.
  def csv_safe(value)
    return value if value.blank?

    FORMULA_PREFIXES.include?(value[0]) ? "'#{value}" : value
  end
end
