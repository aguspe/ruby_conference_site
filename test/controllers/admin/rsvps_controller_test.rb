require "test_helper"

class Admin::RsvpsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_admin_user = ENV["ADMIN_USER"]
    @original_admin_password = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_USER"] = "organiser"
    ENV["ADMIN_PASSWORD"] = "hygge"
    Rsvp.create!(name: "Ada", email: "ada@example.com", dietary: "no nuts")
  end

  teardown do
    ENV["ADMIN_USER"] = @original_admin_user
    ENV["ADMIN_PASSWORD"] = @original_admin_password
  end

  def auth_headers(user = "organiser", password = "hygge")
    { "HTTP_AUTHORIZATION" =>
        ActionController::HttpAuthentication::Basic.encode_credentials(user, password) }
  end

  test "requires credentials" do
    get admin_rsvps_path
    assert_response :unauthorized
  end

  test "rejects wrong credentials" do
    get admin_rsvps_path, headers: auth_headers("organiser", "wrong")
    assert_response :unauthorized
  end

  test "lists rsvps with the seat count" do
    get admin_rsvps_path, headers: auth_headers
    assert_response :success
    assert_match "ada@example.com", response.body
    assert_match "no nuts", response.body
    assert_match "1 / #{Rsvp::CAPACITY}", response.body
  end

  test "exports csv" do
    get admin_rsvps_path(format: :csv), headers: auth_headers
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match "name,email,dietary,waitlisted,created_at", response.body
    assert_match "Ada,ada@example.com,no nuts,false", response.body
  end

  test "rejects unauthenticated csv requests" do
    get admin_rsvps_path(format: :csv)
    assert_response :unauthorized
  end

  test "fails closed when ADMIN_USER is unset" do
    ENV["ADMIN_USER"] = nil
    get admin_rsvps_path, headers: auth_headers
    assert_response :unauthorized
  end

  test "fails closed when ADMIN_USER is blank" do
    ENV["ADMIN_USER"] = ""
    get admin_rsvps_path, headers: auth_headers
    assert_response :unauthorized
  end

  test "fails closed when ADMIN_PASSWORD is unset" do
    ENV["ADMIN_PASSWORD"] = nil
    get admin_rsvps_path, headers: auth_headers
    assert_response :unauthorized
  end

  test "fails closed when ADMIN_PASSWORD is blank" do
    ENV["ADMIN_PASSWORD"] = ""
    get admin_rsvps_path, headers: auth_headers
    assert_response :unauthorized
  end

  test "fails closed when both credentials are unset, even with empty submitted credentials" do
    ENV["ADMIN_USER"] = nil
    ENV["ADMIN_PASSWORD"] = nil
    get admin_rsvps_path, headers: auth_headers("", "")
    assert_response :unauthorized
  end

  test "rejects a wrong-length username without erroring" do
    get admin_rsvps_path, headers: auth_headers("org", "hygge")
    assert_response :unauthorized
  end

  test "rejects a wrong-length password without erroring" do
    get admin_rsvps_path, headers: auth_headers("organiser", "wrong-length-password")
    assert_response :unauthorized
  end

  test "neutralises leading formula characters in csv fields to prevent csv injection" do
    Rsvp.create!(name: "=cmd|'/c calc'!A1", email: "formula@example.com", dietary: "+SUM(1+1)")

    get admin_rsvps_path(format: :csv), headers: auth_headers

    assert_response :success
    refute_match(/,=cmd/, response.body)
    refute_match(/,\+SUM/, response.body)
    assert_match "'=cmd", response.body
    assert_match "'+SUM", response.body
  end

  # --- Fail-closed on whitespace-only credentials ------------------------
  #
  # `" ".empty?` is false, so the original `empty?` guard let a whitespace-only
  # ADMIN_USER/ADMIN_PASSWORD through and served the full attendee list — name,
  # email and dietary/allergy data — to anyone who guessed a single space. A
  # templated env file or a YAML `ADMIN_PASSWORD: " "` produces exactly this,
  # so each whitespace shape is pinned individually rather than as one case.
  WHITESPACE_CREDENTIALS = {
    "a single space" => " ",
    "multiple spaces" => "   ",
    "a tab" => "\t",
    "a newline" => "\n",
    "mixed whitespace" => " \t\n\r "
  }.freeze

  WHITESPACE_CREDENTIALS.each do |label, blank_value|
    test "fails closed when ADMIN_USER is #{label}" do
      ENV["ADMIN_USER"] = blank_value
      get admin_rsvps_path, headers: auth_headers(blank_value, "hygge")
      assert_response :unauthorized
    end

    test "fails closed when ADMIN_PASSWORD is #{label}" do
      ENV["ADMIN_PASSWORD"] = blank_value
      get admin_rsvps_path, headers: auth_headers("organiser", blank_value)
      assert_response :unauthorized
    end

    test "fails closed when both credentials are #{label}" do
      ENV["ADMIN_USER"] = blank_value
      ENV["ADMIN_PASSWORD"] = blank_value
      get admin_rsvps_path, headers: auth_headers(blank_value, blank_value)
      assert_response :unauthorized
    end

    test "fails closed for the csv export when both credentials are #{label}" do
      ENV["ADMIN_USER"] = blank_value
      ENV["ADMIN_PASSWORD"] = blank_value
      get admin_rsvps_path(format: :csv), headers: auth_headers(blank_value, blank_value)
      assert_response :unauthorized
      refute_match "ada@example.com", response.body
    end
  end

  test "rejects the csv export with wrong credentials" do
    get admin_rsvps_path(format: :csv), headers: auth_headers("organiser", "wrong")
    assert_response :unauthorized
    refute_match "ada@example.com", response.body
  end

  # --- CSV injection via the email column --------------------------------
  #
  # `URI::MailTo::EMAIL_REGEXP` does not reject a leading formula character:
  # all of these pass model validation and can be submitted through the real
  # public form, so the export must escape email like any other free text.
  FORMULA_EMAILS = [
    "=a@b.com",
    "+a@b.com",
    "-a@b.com",
    "=SUM@b.com",
    "-2-3@b.com",
    "-2+3@evil.com"
  ].freeze

  FORMULA_EMAILS.each_with_index do |formula_email, index|
    test "escapes a formula-leading email in the csv export: #{formula_email}" do
      rsvp = Rsvp.create!(name: "Mallory#{index}", email: formula_email, dietary: "none")
      # `normalizes :email` only strips and downcases; the formula-leading
      # character survives, and `URI::MailTo::EMAIL_REGEXP` accepts it.
      stored = rsvp.reload.email
      assert_equal formula_email.downcase, stored,
        "expected #{formula_email.inspect} to pass validation with its leading formula character intact"

      get admin_rsvps_path(format: :csv), headers: auth_headers

      assert_response :success
      refute_match(/,#{Regexp.escape(stored)}/, response.body,
        "email #{stored.inspect} reached the export unescaped")
      assert_match "'#{stored}", response.body
    end
  end

  # --- CSV injection via leading whitespace ------------------------------
  #
  # Inspecting `value[0]` only was a bypass: spreadsheet apps trim leading
  # whitespace on import and then evaluate the formula. `dietary` has no
  # `normalizes` strip, so whitespace survives to the export verbatim.
  WHITESPACE_PREFIXES = {
    "a space" => " ",
    "a tab" => "\t",
    "a newline" => "\n",
    "a carriage return" => "\r",
    "mixed whitespace" => " \t\r\n "
  }.freeze

  WHITESPACE_PREFIXES.each_with_index do |(label, prefix), index|
    test "escapes a formula preceded by #{label} in the dietary column" do
      payload = "#{prefix}=1+1"
      rsvp = Rsvp.create!(name: "Diet#{index}", email: "diet#{index}@example.com", dietary: payload)
      assert_equal payload, rsvp.reload.dietary,
        "dietary is expected to keep leading whitespace verbatim"

      get admin_rsvps_path(format: :csv), headers: auth_headers

      assert_response :success
      assert_match "'#{payload}", response.body,
        "dietary #{payload.inspect} reached the export unescaped"
    end

    test "escapes a formula preceded by #{label} in the name column" do
      payload = "#{prefix}=2+2"
      Rsvp.create!(name: payload, email: "namep#{index}@example.com", dietary: "none")

      get admin_rsvps_path(format: :csv), headers: auth_headers

      assert_response :success
      # `normalizes :name` strips, so what reaches the export is the stripped
      # form; either way it must never appear with a bare leading `=`.
      refute_match(/(?<=[,"])=2\+2/, response.body)
      assert_match "'=2+2", response.body
    end

    test "escapes a formula preceded by #{label} in the email column" do
      # Email is stripped by `normalizes`, so the whitespace-prefixed form
      # still lands as a formula-leading value and must be escaped.
      payload = "#{prefix}=w#{index}@b.com"
      Rsvp.create!(name: "Emailp#{index}", email: payload, dietary: "none")

      get admin_rsvps_path(format: :csv), headers: auth_headers

      assert_response :success
      refute_match(/,=w#{index}@b\.com/, response.body)
      assert_match "'=w#{index}@b.com", response.body
    end
  end

  # --- Timing property ---------------------------------------------------
  #
  # The credential check uses `&`, not `&&`, so both `secure_compare` calls
  # always run and the response time cannot reveal whether the username alone
  # was correct. A timing assertion would be flaky, so this is guarded at the
  # source level instead: mutating `&` to `&&` in the controller turns this
  # test red, which a code comment alone could not do.
  test "credential comparison uses non-short-circuiting & so timing does not leak username validity" do
    source = Rails.root.join("app/controllers/admin/rsvps_controller.rb").read
    comparison = source[/secure_compare\(user, expected_user\)\s*(&&?)\s*\n/m, 1]

    refute_nil comparison,
      "could not find the credential comparison in the controller; if it was " \
      "restructured, re-establish the non-short-circuiting property and update this test"
    assert_equal "&", comparison,
      "the credential comparison must use `&`, not `&&`. `&&` short-circuits when " \
      "the username is wrong, so a request with a correct username takes measurably " \
      "longer than one with a wrong username, letting an attacker enumerate the " \
      "username before attacking the password."
  end
end
