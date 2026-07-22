require "csv"

class Admin::RsvpsController < ApplicationController
  before_action :authenticate_organiser

  # Leading characters that spreadsheet applications (Excel, Google Sheets)
  # interpret as the start of a formula when a CSV cell is opened. Attendee
  # names, emails and dietary notes come straight from an anonymous public form, so a
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
      # with empty credentials. `blank?` rather than `empty?` deliberately: a
      # whitespace-only value (`ADMIN_PASSWORD=" "`, or a YAML
      # `ADMIN_PASSWORD: " "`) is not `empty?`, so `empty?` would let a
      # templating accident configure a guessable one-space credential and
      # open the attendee list. `blank?` treats " ", "\t" and "\n" as unset.
      next false if expected_user.blank? || expected_password.blank?

      # `&` and not `&&`, deliberately: `&&` would short-circuit when the
      # username is wrong, skipping the password comparison and making a
      # correct-username request measurably slower than a wrong-username one.
      # `&` always evaluates both, so response time reveals nothing about
      # which half matched. Guarded by a source-level test in
      # test/controllers/admin/rsvps_controller_test.rb.
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
          # Sanitised like any other free-text column. `URI::MailTo::EMAIL_REGEXP`
          # does NOT rule out a leading formula character — `=a@b.com`,
          # `+a@b.com`, `-2-3@b.com` and `=SUM@b.com` all pass validation and
          # can be submitted through the public form.
          csv_safe(rsvp.email),
          csv_safe(rsvp.dietary),
          rsvp.waitlisted,
          rsvp.created_at.iso8601
        ]
      end
    end
  end

  # Prefixes a value with a single quote if its first *non-whitespace*
  # character is one a spreadsheet would treat as a formula trigger. Leaves
  # everything else, and blank/nil fields, untouched.
  #
  # Testing `value[0]` alone was a bypass: `" =1+1"` and `"\t=1+2"` start with
  # whitespace, so they escaped sanitisation, and Excel/Sheets trim leading
  # whitespace on import and then evaluate the cell. `[/\S/]` finds the first
  # non-whitespace character regardless of how much space, tab, newline or
  # carriage return precedes it.
  def csv_safe(value)
    return value if value.blank?

    FORMULA_PREFIXES.include?(value.to_s[/\S/]) ? "'#{value}" : value
  end
end
